//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2020-05-03
// Last modified:  2021-07-30
// Module Name:    fetch
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Instruction fetch and unconditional jump, call, and return
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"

// code address to jump to when reset button is pressed
parameter max_loader_size   = (`MAX_LOADER_SIZE) << 2;          // loader size in words
parameter code_memory_start = 2**`CODE_ADDR_START;
parameter code_memory_size  = 2**(`CODE_ADDR_WIDTH+2);
//parameter code_memory_end   = code_memory_start + code_memory_size;
parameter loader_start_address = code_memory_size - max_loader_size;  // address of loader relative to code memory start, in bytes

// upper 7 bits of instruction word identifying unconditional jump or call
parameter instruction_jump_uncond = 7'b0111100; // next bit is 1 for call, 0 for jump. The rest is 24 bits signed offset
// upper 11 bits of instruction word identifying return instruction
parameter instruction_return  = 11'b01110111110;
// upper 11 bits of instruction word identifying sys_return instruction
parameter instruction_sys_return  = 11'b01111111110;
// upper 4 bits of any 1-word control transfer instruction
parameter instruction_jumpa = 4'b0111;
// upper 8 bits of any 2-word control transfer instruction
parameter instruction_jump2w = 8'b10101000;
// upper 8 bits of any 3-word control transfer instruction
parameter instruction_jump3w = 8'b11001000;
// bit OP1 for push and pop instructions (= 56,57)
parameter instruction_push_pop = 6'b111000;
// upper 11 bits of instruction word identifying read_perfs serializing instruction. Need M bit too
parameter instruction_read_perfs  = 11'b01000100101;


// Fetch module: fetch instructions from memory or code cache
module fetch
(   input clock,                                 // system clock (100 MHz)
    input clock_enable,                          // clock enable. Used when single-stepping
    input reset,                                 // system reset.
    input restart,                               // restart running program     
    input valid_in,                              // valid data from code cache ready
    input stall_in,                              // a later stage in pipeline is stalled
    input jump_in,                               // a jump target is coming from the ALU. jump_pointer has been sent to the code cache
    input nojump_in,                             // signal from ALU that the jump target is the next instruction
    input [`CODE_ADDR_WIDTH-1:0] jump_pointer,   // jump target from ALU
    input [`CODE_DATA_WIDTH-1:0] read_data,      // data from code cache
    input [`CODE_ADDR_WIDTH-1:0] return_pop_data,// Return address popped here at return instruction
    output reg [`CODE_ADDR_WIDTH-2:0] read_addr_out, // read address relative to code memory start
    output reg read_enable_out,                  // code cache read enable
    output reg valid_out,                        // An instruction is ready for output to decoder
    output reg jump_out,                         // A jump instruction is bypassing the pipeline
    output reg [`CODE_ADDR_WIDTH-1:0] instruction_pointer_out, // address of current instruction
    output reg [95:0] instruction_out,           // current instruction, up to 3 words long    
    output reg call_e_out,                       // Executing call instruction. push_data contains return address
    output reg return_e_out,                     // Executing return instruction. return address is available in advance on pop_data
    output reg stall_predict_out,                // Predict that decoder will use multiple clock cycles
    output reg [`CODE_ADDR_WIDTH-1:0] call_push_data_out, // Return address pushed here at call instruction
    output reg [31:0] debug1_out                 // temporary debug output    
);

// Efficient handling of jumps, calls, and returns:
// Unconditional jumps, calls, and returns are executed directly in the fetch unit rather
// than waiting for the instruction to go through the pipeline.
// Conditional and indirect jumps must go to the ALU. The jump target address is fed from the ALU
// directly to the code cache in order to save one clock cycle.
// Direct calls and returns are communicating directly with the call stack.
// Indirect calls are handled in both fetch unit and ALU. The return address is pushed on the 
// call stack by the fecth module while the target address comes from the ALU.
// Return addresses are obtained from the call stack. It takes one clock to send a call or return
// request to the call stack and another clock to retrieve the return address from the stack.
// Therefore, it is not possible to execute a return in the first clock cycle after another
// call or return. The fetch module does not check for this because the second return is delayed
// for a clock cycle anyway to wait for the target to be fetched from the code cache. 

parameter fetch_buffer_size = 8; // number of 32-bit words in instruction fetch buffer

// Name suffixes on local variables: 
// 0: relates to the instruction that is currently in output registers
// 1: relates to the instruction that is being generated in the current clock cycle
// 2: relates to the instruction that will be generated in the next clock cycle

reg [0:fetch_buffer_size-1][31:0] fetch_buffer;  // instruction buffer, (fetch_buffer_size) * 32-bit words
reg   unsigned [3:0] valid_words0;               // number of valid 32-bit words in fetch_buffer
logic unsigned [3:0] valid_words1;               // number of valid words in fetch_buffer in next clock cycle
logic unsigned [1:0] instruction_length0;        // length of current instruction, in 32-bit words
logic unsigned [1:0] instruction_length1;        // length of next instruction, in 32-bit words
logic unsigned [1:0] instruction_length2;        // length of 2. next instruction, in 32-bit words
logic instruction_ready0;                        // current instruction has been fetched
logic instruction_ready1;                        // instruction 1 will be dispatched in next clock cycle 

logic [1:0] buffer_action;   // 0: idle. nothing dispatched. buffer is full or waiting for data
                             // 1: fill buffer. nothing dispatched. new data arriving from code cache
                             // 2: dispatch. instruction 0 is dispatched to the pipeline. shift down data
                             // 3: dispatch and fill.
logic shift_out0;                                // instruction 0 is dispatched in this clock cycle and fetch_buffer is shifted to get the next instruction to position 0
logic unsigned [1:0] dispatch_length0;           // length of dispatched instruction
logic send_next;                                 // send an address to code cache. true if buffer is sure not to overflow in next two clocks
logic [3:0] fetch_buffer_pos;                    // position where to write to fetch_buffer from cache

logic early_jump;                                // jump instruction detected in instruction 1 or 2
logic conditional_jump;                          // a conditional or indirect jump or call detected in instruction 1. Wait for ALU to find target
logic [1:0] call_instruction;                    // 1: any kind of call or trap detected in instruction 1 or 2. Push return address on stack
                                                 // 2: return or system return instruction detected. pop return address from stack
logic unsigned [`CODE_ADDR_WIDTH-1:0] early_jump_addr; // target address for early jump
reg unsigned [`CODE_ADDR_WIDTH:0] jump_target;   // save jump target address. may be calculated here for unconditional jump, or input from ALU for conditional jump
logic unsigned [`CODE_ADDR_WIDTH:0] reset_target;// Address of loader or restart code
reg restart_underway;                            // remember restarting is in process

logic unsigned [`CODE_ADDR_WIDTH-1:0] return_addr; // return address after call instruction
logic [31:0] word1;                              // first word of instruction 1
logic unsigned [`CODE_ADDR_WIDTH-1:0] instruction_pointer1; // address of instruction 1

reg [3:0] jump_case;  // for debug display only. may be removed
  
// It takes two clock cycles to fetch data from the code cache: one clock to send an address to 
// the code cache, and one clock to send the data from the code cache.
// The following three shift registers are keeping track for the data that is underway:
// next_underway is tracking sequential code, target_underway is tracking jump targets,
// and wait_for_target tells that we are waiting for a jump target to be calculated and fetched.

reg [1:0] next_underway; // target_underway is a shift register indicating that code words are underway from the code cache
// next_underway is shifted right with zero extension
// next_underway[0]: data arrived from code cache
// next_underway[1]: next address has been sent to code cache

reg [2:0] target_underway;  // target_underway is a shift register indicating that a jump target is underway:
// target_underway is shifted right with zero extension
// 100: system reset
// 010: wait for target to be fetched from code cache
// 001: target code is inserted in fetch_buffer. Clear wait_for_target

reg wait_for_target; // wait_for_target indicates that an unconditional jump, call, or return
// is waiting for the target to be fetched from the code cache

reg wait_for_jump; // wait_for_jump indicates that a conditional or indirect jump or call
// has been dispatched and is waiting for the ALU to deliver the target address


// Analyze the status of fetch_buffer:
always_comb begin

    // if (restart == 0): Start address is loader address 
    // if (restart == 1): Start address is restart address = loader address + 1 
    reset_target = {loader_start_address >> 3, (restart | restart_underway)};    
    
    // Find length and position of instruction 0 
    if (valid_words0 > 0) begin
        instruction_length0 = fetch_buffer[0][31] ? fetch_buffer[0][31:30] : 2'b01; // the length of instruction 0
        // instruction 0 is ready if all words belonging to the instruction are fetched.
        instruction_ready0 = (valid_words0 >= instruction_length0) && !target_underway[0] && !wait_for_target;
        shift_out0 = instruction_ready0 & !stall_in & !reset & (!wait_for_jump | nojump_in);  // instruction 0 will be dispatched in this clock cycle
    end else begin
        // First instruction has not been fetched yet
        instruction_length0 = 0;
        instruction_ready0 = 0;
        shift_out0 = 0;
    end
    
    // number of words dispatched
    if (shift_out0) 
        dispatch_length0 = instruction_length0;
    else
        dispatch_length0 = 0;    
    
    // check if we can fill the buffer
    if ((target_underway[0] | early_jump | jump_in) & valid_in) begin  // overwrite buffer with new jump target
        send_next = 1;
        fetch_buffer_pos = 0;
    end else begin
        if (shift_out0) begin
            fetch_buffer_pos = valid_words0 - instruction_length0;
        end else begin
            fetch_buffer_pos = valid_words0;        
        end
        
        // determine whether we will fetch the next doubleword from the code cache.
        // maybe this can be tweaked a little better, but make sure the fetch buffer cannot overflow in case of stalls 
        if (next_underway[0] & valid_in & next_underway[1]) begin
            send_next = fetch_buffer_pos < fetch_buffer_size - 6;
        end else if ((next_underway[0] & valid_in) | next_underway[1]) begin
            send_next = fetch_buffer_pos < fetch_buffer_size - 4;
        end else begin
            send_next = fetch_buffer_pos < fetch_buffer_size - 2;
        end
    end 

    buffer_action[0] = (next_underway[0] | target_underway[0]) & valid_in;  // fill buffer
    buffer_action[1] = shift_out0;  // instruction 0 dispatched. shift down buffer 

    // predict if the next instruction, i.e. instruction 1, will be ready in next clock cycle
    if (target_underway[0] & valid_in) begin
        if (jump_target[0]) 
            valid_words1 = 1;  // jumping to an odd address. use only the upper half of read_data
        else 
            valid_words1 = 2;  // jumping to even address. use 64 bits read_data
    end else if (wait_for_target) begin
        valid_words1 = 0;
    end else begin 
        if (next_underway[0] & valid_in) 
            valid_words1 = valid_words0 - dispatch_length0 + 2;
        else 
            valid_words1 = valid_words0 - dispatch_length0;
    end
    
    // Find first word of instruction 1 for the sake of early jump detection and predecoding.
    //  (Here, I am shortening the critical path 
    //   valid_words0 -> instruction_length0 -> instruction_ready0 -> shift_out0 -> dispatch_length0
    //   -> valid_words1 -> word1 -> instruction_length1 -> early_jump_addr -> instruction_pointer_out
    //   by postponing "if (valid_words1 != 0)") 
    if (target_underway[0] && valid_in) begin  // get instruction1 from jump target
        if (jump_target[0]) begin
            word1 = read_data[63:32]; // jumping to odd address
        end else begin
            word1 = read_data[31:0];
        end
        instruction_pointer1 = jump_target;
        instruction_length1 = word1[31] ? word1[31:30] : 2'b01; // length of second instruction
    end else if (valid_words0 > instruction_length0) begin // instruction 1 is already in buffer
        word1 = fetch_buffer[instruction_length0];
        instruction_pointer1 = instruction_pointer_out + instruction_length0;
        instruction_length1 = word1[31] ? word1[31:30] : 2'b01; // length of second instruction
        
    end else if (valid_words0 == instruction_length0) begin // instruction 1 is going into buffer in this clock cycle
        word1 = read_data[31:0];
        instruction_pointer1 = instruction_pointer_out + instruction_length0;
        instruction_length1 = word1[31] ? word1[31:30] : 2'b01; // length of second instruction

    end else if (valid_words0 > 0) begin // instruction 1 is partially in buffer
        word1 = fetch_buffer[0];
        instruction_pointer1 = instruction_pointer_out;
        instruction_length1 = word1[31] ? word1[31:30] : 2'b01; // length of second instruction
           
    end else begin
        word1 = 0;
        instruction_pointer1 = 0; //64'HXXXXXXXXXXXXXXXX;
        instruction_length1  = 3; // indicate not ready
    end


    // Look for jump, call, and return instructions in instruction 1
    // in order to fetch target as early as possible.
    // This is done in the following way:
    // Unconditional jumps, calls, and returns are handled as early as possible in order
    // to fetch early from the target address and thereby save time. However,
    // we have to check if there is a preceding jump or call in a preceding position in 
    // fetch_buffer before we execute a jump, call, or return in position 2.
    // Conditional and indirect jumps are detected when they are in position 0 in fetch_buffer,
    // and we have to wait for the ALU to find the target address.
    // Indirect calls are are also detected when they are in position 0 in fetch_buffer:
    // the return address is pushed on the call stack while we wait for the ALU to find the target address.
    // The following variables tell what we have found here:
    // early_jump:    An unconditional jump, call, or return detected in position 1 or 2.
    // conditional_jump: A conditional or indirect jump or call is detected. Wait for ALU to find target
    // call_instruction: 1: any kind of call detected. Push return address on stack
    //                   2: a return or sys_return instruction detected. Pop return address from stack
    
    conditional_jump = 0;
    early_jump = 0;
    early_jump_addr = 0;
    call_instruction = 0;
    return_addr = 0;
    
    instruction_ready1 = (valid_words1 >= instruction_length1) & !reset && (!wait_for_jump | nojump_in);  // instruction 1 will be dispatched in next clock cycle
    //valid_out <= valid_words1 >= instruction_length1 & !reset && !early_jump & target_underway[2:1] == 0 & (!wait_for_jump | nojump_in);
    

    if (valid_words1 != 0 && word1[31:28] == instruction_jumpa) begin
        // Any single-word control transfer instruction is underway
        if ((word1[31:25] == instruction_jump_uncond) & !stall_in & (!wait_for_jump | nojump_in)) begin
            // unconditional jump or call instruction found in instruction 1
            early_jump = 1; 
            early_jump_addr = $signed(word1[23:0]) + instruction_pointer1 + 1; // add 24-bit signed offset to address of end of instruction
            call_instruction = word1[24]; // 0: unconditional jump, 1: direct call
            return_addr = instruction_pointer1 + instruction_length1; // return address for call instruction
        end else if ((word1[31:21] == instruction_return || word1[31:21] == instruction_sys_return) & !stall_in & (!wait_for_jump | nojump_in)) begin
            // a return instruction is found in the first instruction
            early_jump = 1; 
            early_jump_addr = return_pop_data;  // get return address from call stack
            call_instruction = 2;              // 2 means return instruction
            return_addr = 0;
        end else if ((word1[`OP1] == `IJ_JUMP_INDIRECT_MEM+1 || word1[`OP1] == `IJ_JUMP_RELATIVE+1 || word1[`OP1] == `IJ_SYSCALL) & !stall_in & (!wait_for_jump | nojump_in)) begin
            // an indirect call or system call instruction is found in the first instruction
            early_jump = 0; 
            early_jump_addr = 0;
            return_addr = instruction_pointer1 + instruction_length1; // return address to push on call stack
            conditional_jump = 1;  // this instruction must go the the ALU
            if (word1[`OP1] == `IJ_TRAP && word1[`MODE] == 7) begin
                // Trap or breakpoint in format 1.7C (IJ_TRAP == IJ_SYSCALL)
                // The breakpoint instruction should not push a return address on the call stack as long
                // as it only activates single step mode without calling any interrupt service routine.
                // Note: this code must be changed if any traps or trap instructions go to an interrupt 
                // service routine that ends with a return or a system return.
                // Setting call_instruction to 1 here will make the next return instruction fail if the 
                // trap does not end with a return.
                call_instruction = 0;  
            end else begin
                // All other indirect call and system call instructions
                call_instruction = 1;            
            end
        end else begin
            // other conditional or indirect jump instruction found in instruction 1
            early_jump = 0; 
            early_jump_addr = 0;
            call_instruction = 0;
            conditional_jump = 1;  // this instruction must go the the ALU
            return_addr = 0;
        end       

    end else if (valid_words1 > 1 && word1[31:24] == instruction_jump2w) begin
        // any double-word jump or call instruction found in the instruction 1
        early_jump = 0;
        early_jump_addr = 0;
        conditional_jump = 1;           // this instruction must go the the ALU
        if (word1[5:0] == `IJ_JUMP_INDIRECT_MEM + 1  // indirect call
        ||  word1[5:0] == `IJ_JUMP_RELATIVE + 1  // call with relative pointer
        ||  word1[5:0] == `IJ_SYSCALL  // system call
        ||  word1[`OP1] == 7 // system call
        )   begin
            call_instruction = !stall_in & (!wait_for_jump | nojump_in);  // push return address on stack
            return_addr = instruction_pointer1 + instruction_length1;
        end else begin
            call_instruction = 0;
            return_addr = 0;
        end
        
    end else if (valid_words1 > 2 && word1[31:24] == instruction_jump3w) begin
        // any triple-word jump or call instruction found in first instruction
        early_jump = 0;
        early_jump_addr = 0;
        conditional_jump = 1;           // this instruction must go the the ALU
        if (word1[5:0] == `IJ_JUMP_INDIRECT_MEM+1  // 64-bit call
        ||  word1[5:0] == `IJ_SYSCALL  // system call
        ) begin
            call_instruction = !stall_in & (!wait_for_jump | nojump_in);  // push return address on stack
            return_addr = instruction_pointer1 + instruction_length1;
        end else begin
            call_instruction = 0;
            return_addr = 0;
        end
    end else if (valid_words1 != 0 && word1[31:21] == instruction_read_perfs && word1[`M]) begin
        // the serializing instruction read_perfs must flush the pipeline. 
        // Use the conditional jump mechanism for this, and give a nojump_in when ready to resume feeding the pipeline 
        conditional_jump = 1;           // serializing instruction read_perfs
    end
end


// Generate code for all possible inputs to each word in fetch_buffer.
// The current instruction is removed, and the rest of fetch_buffer is shifted down to make space for next 2 words of code
// Data from the code cache are inserted into the first vacant space of fetch_buffer
genvar i;
generate
    // generation loop for each word in fetch_buffer
    for (i = 0; i < fetch_buffer_size; i++) begin
        always_ff @(posedge clock) if (clock_enable) begin

            if (i < fetch_buffer_pos && buffer_action[1]) begin
                // instruction 0 is being dispatched. shift down
                fetch_buffer[i][31:0] <= fetch_buffer[i+instruction_length0][31:0];
                
            end else if (i == fetch_buffer_pos && buffer_action[0]) begin
                // load first word 
                if (target_underway[0] & jump_target[0]) begin
                    // jumping to an odd address. use only upper half of read_data
                    fetch_buffer[i][31:0] <= read_data[63:32];
                end else begin            
                    // load first word
                    fetch_buffer[i][31:0] <= read_data[31:0];
                end
        
            end else if (i == fetch_buffer_pos + 1 && buffer_action[0]) begin
                // load second word
                fetch_buffer[i][31:0] <= read_data[63:32];
                
            end
        end
    end
endgenerate


// Calculate read_addr and instruction_pointer in next clock cycle
// The shift registers named target_underway and wait_for_target indicate if we are waiting for a jump target
always_ff @(posedge clock) if (clock_enable) begin

    valid_words0 <= valid_words1;
    read_enable_out <= send_next;
    
    if (!stall_in) begin
        // send instruction to the decoder
        valid_out <= instruction_ready1 && !early_jump;

        // Unconditional jumps are bypassing the pipeline
        jump_out <= early_jump;
        
    end else if (instruction_ready1 && !early_jump) begin
    
        // Turn valid_out on, but not off, when there is stall_in.
        // This is necessary if there is a stall one instruction before a fast jump,
        // causing the jump bubble to be filled. Otherwise, it skips the first instruction after the jump
        valid_out <= 1;
    end    
    
    jump_case <= 0;
    
    if (reset) begin
        // reset button pressed
        if (restart) restart_underway <= 1;
        next_underway <= 2'b00;
        target_underway <= 3'b100;
        wait_for_target <= 1;
        wait_for_jump <= 0;
        jump_target <= reset_target;
        read_addr_out <= reset_target >> 1;
        instruction_pointer_out <= reset_target;
        valid_words0 <= 0;        
        read_enable_out <= 0;
        valid_out <= 0;
        jump_out <= 0; 
                
    end else if (target_underway[2]) begin
        // first clock after reset
        jump_case <= 1;
        next_underway <= 2'b00;
        target_underway <= {1'b0,target_underway[2:1]}; // shift right to indicate when jump target arrives  
        wait_for_target <= 1;  // skip all instructions until jump target arrives
        instruction_pointer_out <= reset_target;
        jump_target <= reset_target;
        read_addr_out <= reset_target >> 1;
    
    end else if (early_jump) begin
        // unconditional jump detected in instruction 1
        jump_case <= 2;
        next_underway <= 2'b00;
        target_underway <= 3'b010;     // wait 2 clock cycles for target
        read_addr_out <= early_jump_addr >> 1;
        jump_target <= early_jump_addr;
        restart_underway <= 0;
        if (!stall_in) begin  
            wait_for_target <= 1;      // skip all instructions until jump target arrives
            wait_for_jump <= 0;
            instruction_pointer_out <= early_jump_addr;
        end

    end else if (conditional_jump && (instruction_ready1 & !stall_in || shift_out0)) begin 
        // conditional jump detected in instruction 1
        jump_case <= 3;
        next_underway <= {send_next,next_underway[1]}; // shift right to indicate when data arrives
        target_underway <= 3'b000;  // wait 2 clock cycles for target  
        // read address is two words ahead because reading takes 2 clock cycles
        if (send_next) begin
            read_addr_out <= read_addr_out + 1;
        end
        wait_for_jump <= 1; // wait for jump target address from ALU
        jump_target <= 0;
        wait_for_target <= 0;
        if (shift_out0) begin
            // point to next instruction
            instruction_pointer_out <= instruction_pointer_out + instruction_length0;            
        end
        /*if (!stall_in) begin
            jump_target <= 0;
            wait_for_target <= 0;
        end*/
    
    end else if (target_underway[0] & valid_in) begin 
        // a jump target has arrived from code cache. (ignore any subsequent jump instructions)
        restart_underway <= 0;
        jump_case <= 4;
        next_underway <= {send_next, next_underway[1]}; // shift right to indicate when data arrives
        wait_for_target <= 0; // stop waiting for jump target
        target_underway <= 3'b000;
        read_addr_out <= read_addr_out + 1;
        if (!stall_in) begin        
            instruction_pointer_out <= jump_target; // set address of current instruction
        end       
   
    end else if (jump_in & wait_for_jump & valid_words1 >= instruction_length1) begin
        // a conditional or indirect jump instruction has been executed in ALU
        // the ALU has sent the target address directly to the code cache to save one clock cycle  
        //next_underway <= 2'b00;
        restart_underway <= 0;
        jump_case <= 5;
        next_underway <= {send_next, next_underway[1]}; // shift right to indicate when data arrives
        target_underway <= 3'b001;   // wait one clock cycle for target
        if (!stall_in) begin        
            wait_for_jump <= 0;
            read_addr_out <= (jump_pointer >> 1) + 1;
            wait_for_target <= 1;
            jump_target <= jump_pointer;
            instruction_pointer_out <= jump_pointer;
        end

    end else if (nojump_in & wait_for_jump) begin
        // a conditional or indirect jump instruction has been executed in ALU
        // and the target is the next instruction  
        //next_underway <= {send_next,next_underway[1]}; // shift right to indicate when data arrives
        restart_underway <= 0;
        jump_case <= 6;
        next_underway <= {send_next, next_underway[1]}; // shift right to indicate when data arrives
        target_underway <= 3'b000;   // wait two clock cycles for target
        wait_for_target <= 0;
        wait_for_jump <= 0;
        if (send_next) begin
            read_addr_out <= read_addr_out + 1;
        end
        // if (!stall_in) begin        
        if (shift_out0) begin
            instruction_pointer_out <= instruction_pointer_out + instruction_length0;
        end 
                   
    end else begin
        // no new jump instruction
        restart_underway <= 0;
        jump_case <= 7;
        next_underway <= {send_next,next_underway[1]};  // shift right to indicate when data arrives
        target_underway <= {1'b0,target_underway[2:1]}; // shift right to indicate when jump target arrives
        
        // make ready for next read. Least significant address bit ignored because data bus is double size  
        // read address is two words ahead because reading takes 2 clock cycles
        if (send_next) begin
            read_addr_out <= read_addr_out + 1;
        end
        if (shift_out0) begin
            // point to next instruction
            instruction_pointer_out <= instruction_pointer_out + instruction_length0;            
        end
        
    end
    
    // communicate with call stack as soon as a call or return instruction is detected.
    // checking !target_underway[0] && !wait_for_target[0] to avoid seding the call_e_out
    // or return_e_out multiple times
    if (reset || target_underway[2:1] != 0) begin
        call_e_out <= 0; 
        return_e_out <= 0;  
        call_push_data_out <= 0;            
    end else if (call_instruction == 1) begin
        call_e_out <= 1; 
        return_e_out <= 0;
        call_push_data_out <= return_addr;
    end else if (call_instruction == 2) begin
        return_e_out <= 1;
        call_e_out <= 0; 
        call_push_data_out <= 0;
    end else begin
        call_e_out <= 0; 
        call_push_data_out <= 0;
        return_e_out <= 0;
    end
    
    // predict that decoder will use multiple clock cycles for push and pop instructions
    if (valid_words1 != 0 && word1[`IL] == 2'b01 && (word1[`MODE] == 3'b011 || (word1[`MODE] == 3'b00 && word1[`M]))
    && word1[`OP1] >> 1 == instruction_push_pop >> 1 && shift_out0) begin
        stall_predict_out <= 1;  // mode = 1.3 or 1.8, op1 = 56 or 57
    end else begin
        stall_predict_out <= 0; 
    end 
    
    // collect various signals for debugging purpose
    debug1_out[0]    <= early_jump;
    debug1_out[1]    <= conditional_jump;
    debug1_out[3]    <= stall_in;    
    
    debug1_out[6:4]  <= valid_words1[2:0];
    debug1_out[7]    <= instruction_ready1;
    
    debug1_out[8]    <= buffer_action[0]; // fill buffer
    debug1_out[9]    <= buffer_action[1]; // shift_out0;
    debug1_out[11:10]<= dispatch_length0;
        
    debug1_out[15:12]<= fetch_buffer_pos;
    
    debug1_out[16]   <= send_next;
    debug1_out[17]   <= instruction_ready0;
    debug1_out[18]   <= nojump_in;
    debug1_out[19]   <= jump_in;
end 
    // register variables are assigned to avoid an extra clock delay:
    assign debug1_out[21:20] = next_underway;
    assign debug1_out[23:22] = target_underway[1:0];
    
    assign debug1_out[27:24] = jump_case; // jump handling case
    
    assign debug1_out[28]  = wait_for_target;
    assign debug1_out[29]  = wait_for_jump;
    assign debug1_out[31]  = valid_out;


// output instruction, 1-3 words   
assign instruction_out[31:0]  = fetch_buffer[0][31:0];
assign instruction_out[63:32] = fetch_buffer[1][31:0];
assign instruction_out[95:64] = fetch_buffer[2][31:0];

endmodule
