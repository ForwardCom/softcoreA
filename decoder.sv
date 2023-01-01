//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2020-05-30
// Last modified:  2022-12-25
// Module Name:    decoder
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Instruction decoder. Identifies instruction category and format, 
// Loads register parameters. Generates multiple µops for push and pop instructions.
// Note that not all decoding is done here. There is further decoding in the 
// address generator and dataread stages.
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"


module decoder (
    input clock,                            // system clock
    input clock_enable,                     // clock enable. Used when single-stepping
    input reset,                            // system reset. 
    input valid_in,                         // data from fetch module ready
    input stall_in,                         // a later stage in pipeline is stalled
    input [`CODE_ADDR_WIDTH-1:0] instruction_pointer_in, // address of current instruction
    input [95:0] instruction_in,            // current instruction, up to 3 words long
    // monitor tags written to register file:
    input write_en1,                        // a result is written to writeport1
    input [`TAG_WIDTH-1:0] write_tag1,      // tag of result inwriteport1
    input write_en2,                        // a result is written to writeport2
    input [`TAG_WIDTH-1:0] write_tag2,      // tag of result inwriteport2    
    output reg        valid_out,            // An instruction is ready for output to next stage
    output reg [`CODE_ADDR_WIDTH-1:0] instruction_pointer_out, // address of current instruction
    output reg [95:0] instruction_out,      // first word of instruction    
    output reg        stall_predict_out,    // Not ready to receive next instruction
    output reg [5:0]  tag_a_out,            // register number for instruction tag
    output reg [`TAG_WIDTH-1:0] tag_val_out,// instruction tag value
    output reg        tag_write_out,        // instruction tag write enable
    output reg        vector_out,           // this is a vector instruction
    output reg [1:0]  category_out,         // 00: multiformat, 01: single format, 10: jump
    output reg [1:0]  format_out,           // 00: format A, 01: format E, 10: format B, 11: format C (format D never goes through decoder)
    output reg [2:0]  rs_status_out,        // what RS is used for
    output reg [2:0]  rt_status_out,        // what RT is used for
    output reg [1:0]  ru_status_out,        // what RU is used for
    output reg [1:0]  rd_status_out,        // what RD is used for
    output reg [1:0]  mask_status_out,      // what the mask register is used for
    output reg        mask_options_out,     // mask register may contain option bits
    output reg        mask_alternative_out, // mask register and fallback register used for alternative purposes
    output reg [2:0]  fallback_use_out,     // 0: no fallback, 1: same as first source operand, 2-4: RU, RS, RT
    output reg [1:0]  num_operands_out,     // number of source operands
    output reg [1:0]  result_type_out,      // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    output reg [1:0]  offset_field_out,     // address offset. 0: none, 1: 8 bit, possibly scaled, 2: 16 bit, 3: 32 bit
    output reg [1:0]  immediate_field_out,  // immediate data field. 0: none, 1: 8 bit, 2: 16 bit, 3: 32 or 64 bit
    output reg [1:0]  scale_factor_out,     // 00: index is not scaled, 01: index is scaled by operand size, 10: index is scaled by -1
    output reg        index_limit_out,      // The field indicated by offset_field contains a limit to the index
    output reg        multi_finish_out,     // An instruction generating multiple micro-ops is finishing    
    output reg        error_out,            // Error in format or parameter
    output reg [31:0] debug1_out            // Temporary output for debugging purpose    
);

logic [1:0]  register_type;                 // 1: general purpose registers, 2: vector registers
logic [1:0]  category;                      // 00: multiformat, 01: single format, 10: jump
logic [1:0]  format;                        // 00: format A, 01: format E, 10: format B, 11: 
                                            // format C (format D never goes through decoder)
logic [1:0]  num_operands;                  // number of source operands
logic [2:0]  rs_status;                     // use of RS register
logic [2:0]  rt_status;                     // use of RT register
logic [1:0]  ru_status;                     // use of RU register
logic [1:0]  rd_status;                     // use of RD register for input
logic        mask_used;                     // 1: mask register is used
logic        mask_options;                  // mask register may contain options
logic [2:0]  fallback_use;                  // 0: no fallback, 1: same as first source operand, 2-4: RU, RS, RT 
logic [1:0]  scale_factor;                  // 00: index is not scaled, 01: index is scaled by operand size, 
                                            // 10: index is scaled by -1
logic [1:0]  offset_field;                  // address offset. 0: none, 1: 8 bit, possibly scaled, 2: 16 bit,
                                            // 3: 32 bit
logic [1:0]  immediate_field;               // immediate data field. 0: none, 1: 8 bit, 2: 16 bit, 3: 32 or 64 bit
logic        index_limit;                   // The field indicated by offset_field contains a limit to the index   
logic        broadcast;                     // Broadcast scalar memory operand or immediate operand
logic [1:0]  result_type;                   // type of result: 0: register, 1: system register, 2: memory,
                                            // 3: other or nothing
logic        format_error;                  // unknown or unsupported instruction format
logic [1:0]  il;                            // instruction length
logic [2:0]  mode;                          // instruction mode
logic [5:0]  op1;                           // OP1 in instruction
logic        M;                             // M bit
logic [1:0]  op2;                           // OP2 in E format
logic [2:0]  mode2;                         // mode2 in E format
logic        mask_alternative;              // mask register and fallback register used for alternative purposes

// variables for generating tag values
reg [`TAG_WIDTH-1:0]      current_tag = 1;  // sequential instruction tags
reg [(2**`TAG_WIDTH)-1:0] tag_used = 0;     // remember which tags are in use
logic [`TAG_WIDTH-1:0]    max_tag;          // maximum tag value = (2**`TAG_WIDTH)-1
logic [`TAG_WIDTH-1:0]    next1;            // next possible tag value after current_tag
logic [`TAG_WIDTH-1:0]    next2;            // next possible tag value after next1
logic [`TAG_WIDTH-1:0]    next3;            // next possible tag value after next2
logic [`TAG_WIDTH-1:0]    next_tag;         // next instruction tag after skipping any tag in use
logic [`TAG_WIDTH-1:0]    next_next_tag;    // 2. next instruction tag after skipping any tag in use

// variables for instructions generating multiple micro-ops
reg          multi_op = 0;                  // the decoder is generating multiple micro-ops for current instructions
logic        push_instruction;              // a push instruction is being decoded
logic        pop_instruction;               // a pop instruction is being decoded
logic        multi_first;                   // first clock cycle of a multi instruction
logic        multi_last;                    // last clock cycle of a multi instruction
logic        multi_last_next;               // multi instruction will end in next clock cycle
logic [3:0]  pop_increment;                 // address increment/decrement for push/pop instructions
logic        decrement_before;              // decrement pointer before write
logic        increment_after;               // increment pointer after read or write
logic        reverse_register_order;        // take last register first
logic        push_pop_error;                // wrong register order or push/pop of stack pointer


//  ***********  Analyze instruction  ***********
always_comb begin
    il   = instruction_in[`IL];
    mode = instruction_in[`MODE];
    op1  = instruction_in[`OP1];
    M    = instruction_in[`M];
    op2  = instruction_in[`OP2];
    mode2 = instruction_in[`MODE2];
    num_operands = 2;
    ru_status = 0;
    rd_status = 0;
    mask_used = 0;
    mask_options = 0;    
    mask_alternative = 0;
    format_error = 0;

    // *** detect instruction format: A, B, C, or E (format D never comes to the decoder) ***
    if (il == 0) begin // format 0.x
        if (mode == 1 || mode == 3 || mode == 7) begin
            format = `FORMAT_B;        // 0.1, 0.3, 0.7, 0.9
        end else begin
            format = `FORMAT_A;        // 0.0, 0.2, 0.4, 0.5, 0.6, 0.8
        end
    
    end else if (il == 1) begin        // format 1.x
        if (mode == 3 || (mode == 0 && M)) begin
            format = `FORMAT_B;        // 1.3, 1.8
        end else if (mode == 6) begin  // 1.6 jump instructions
            if (op1 == `II_RETURN) format = `FORMAT_C;  // return
            else if (op1 >= `II_JUMP_RELATIVE) begin
                format = `FORMAT_A;    // relative jump, sys_call
            end else format = `FORMAT_B;
        end else if (mode == 1 || mode == 4 || mode == 7) begin
            format = `FORMAT_C;        //1.1, 1.4, 1.7
        end else begin
            format = `FORMAT_A;        // 1.0, 1.2
        end

    end else if (il == 2) begin        // format 2.x
        if ((mode == 0 && M == 0) || mode == 2) begin
            format = `FORMAT_E;        // 2.0.x, 2.2.x
            
        end else if (mode == 5) begin  // format 2.5 mixed
            if (op1 == 0)      format = `FORMAT_A; // jump format 2.5.0A
            else if (op1 <= 3) format = `FORMAT_B; // jump format 2.5.1B, 2.5.2B
            else if (op1 <= 7) format = `FORMAT_C; // jump format 2.5.4C - 2.5.7C
            else if (op1 >= `II_25_VECT) format = `FORMAT_A;  // 2.5 32-63 vector instructions 
            else format = `FORMAT_B;   // other miscellaneous instructions 
            
        end else begin
            format = `FORMAT_A;        // other formats 2.x 
        end
        
    end else begin // format 3.x
        if ((mode == 0 && M == 0) || mode == 2) begin
            format = `FORMAT_E;        // 3.0.x, 3.2.x
        end else if (mode == 1) begin  // 3.1 mixed
            if (op1 > 0 && op1 < 8) begin // jump instructions 3.1.1 - 3.1.7
                format = `FORMAT_B;
            end else begin
                format = `FORMAT_A;
            end
        end else begin
            format = `FORMAT_A;
        end
    end            

    // *** detect category ***
    // 00: multiformat, 01: single format, 10: jump
    // (this differs from the category numbers in instruction_list.cvs)
    if (il == 0) begin // format 0.x
        category = `CAT_MULTI;
        
    end else if (il == 1) begin             // format 1.x
        if (mode == 6 || mode == 7) begin   // format 1.6 and 1.7
            category = `CAT_JUMP;
        end else begin
            category = `CAT_SINGLE;
        end
        
    end else if (il == 2 && ((mode == 0 && !M) || mode == 2) && op2 != 0 && mode2 != 5) begin 
        // op2 > 0 in format 2.0.x, 2.2.x, except 2.0.5, 2.2.5
        category = `CAT_SINGLE;

    end else if (il == 3 && ((mode == 0 && !M) || mode == 2) && op2 != 0) begin 
        // op2 > 0 in format 3.0.x, 3.2.x 
        category = `CAT_SINGLE;
        
    end else if (il == 2) begin             // format 2.x
        if (mode == 1 && M) begin           // format 2.9
            category = `CAT_SINGLE;
        end else if (mode == 6 || mode == 7) begin // format 2.6 - 2.7
            category = `CAT_SINGLE;
        end else if (mode == 5) begin       // format 2.5
            if (op1 < 8) begin
                category = `CAT_JUMP;
            end else begin
                category = `CAT_SINGLE;
            end            
        end else begin
            category = `CAT_MULTI;
        end
        
    end else begin                          // format 3.x
        if (mode == 1) begin                // format 3.1
            if (op1 < 8) begin
                category = `CAT_JUMP;
            end else begin
                category = `CAT_SINGLE;
            end
        end else begin
            category = `CAT_MULTI;
        end
    end
            
    // is this a vector instruction?
    register_type = `REG_OPERAND;
    if (category == `CAT_JUMP) begin
        if (M && format != `FORMAT_C) register_type = `REG_VECTOR; 
    end else if (il == 2 && mode == 5) begin // 2.5 mixed 
        if (op1 >= `II_25_VECT) register_type = `REG_VECTOR; 
    end else if (il == 3 && mode == 1) begin // 3.1 mixed 
        if (op1 >= `II_31_VECT) register_type = `REG_VECTOR; 
    end else if (mode >= 2) begin
        register_type = `REG_VECTOR;
    end
    
    // *** count number of operands and mask use ***
    if (category == `CAT_MULTI) begin
        if (op1 == `II_NOP) num_operands = 0;
        else if (op1 <= `II_ONE_OP) num_operands = 1;
        else if (op1 >= `II_3OP_FIRST && op1 <= `II_3OP_LAST) begin 
            num_operands = 3;
            // There are currently no g.p. instructions that have option bits in a mask register.
            // To do: Set mask_options for relevant floating point instructions
            // if (format != `FORMAT_A && format != `FORMAT_E) mask_options = 1; 
        end
        if ((format == `FORMAT_E || format == `FORMAT_A) && (op1 == `II_COMPARE || op1 == `II_TEST_BIT || op1 == `II_TEST_BITS_AND || op1 == `II_TEST_BITS_OR)) begin
            mask_alternative = 1; // these instructions allow alternative use of mask register and fallback register
        end 
    end else if (il == 1 && mode == 1) begin               // format 1.1 C 
        // (don't check M because there is no M bit in format C)
        if (op1 <= `II_MOVE11_LAST) num_operands = 1;      // move

    end else if (il == 1 && mode == 2) begin               // format 1.2 A
        if (op1 <= `II_GETNUM_12) num_operands = 1;
        if (op1 == `II_OUTPUT_18) num_operands = 3;        // output instruction
        
    end else if (il == 1 && mode == 0 && M) begin          // format 1.8
        if (op1 == `II_VECTORS_USED) num_operands = 0;     // vectors_used instruction
        if (op1 == `II_OUTPUT_18)  num_operands = 3;       // output instruction

    end else if (il == 2 && mode == 6) begin               // format 2.6 A
        if (op1 == `II_LOAD_HI_26) num_operands = 1;       // load_hi instruction  

    end else if (il == 2 && mode == 1 && M) begin          // format 2.9 A
        if (op1 == `II_MOVE_HI_29 || op1 == `II_ADDRESS_29) num_operands = 1; // mov or address instruction

    end else if (il == 2 && (mode == 0 && !M || mode == 2)) begin // format 2.0.x, 2.2.x
        if (mode2 == 6 && op1 == `II_TRUTH_TAB3 && op2 == `II2_TRUTH_TAB3) begin 
            num_operands = 3;                              // truth_tab3. 3 operands
        end
        if (mode2 == 7 && op1 == `II_MOVE_BITS && op2 == `II2_MOVE_BITS) begin 
            num_operands = 3;                              // move_bits. 3 operands 
            // (Actually 5 operands: IM4 contains two 6-bit constants, IM5 contains the last operand)
        end

    end else if (category == `CAT_JUMP) begin
        if (il == 1 && mode == 6) begin
            if (op1 >> 1 == `IJ_JUMP_INDIRECT_MEM >> 1) num_operands = 1;
            else if (op1 >> 1 == `IJ_RETURN >> 1) num_operands = 0;
            
        end else if (il == 1 && mode == 7) begin
            if (op1 >> 1 == `IJ_JUMP_INDIRECT_REG >> 1) num_operands = 1;
            else if (op1 == `IJ_SYSRETURN || op1 == `IJ_TRAP) num_operands = 0;        
            
        end else if (il == 2 && mode == 5 && instruction_in[5:1] == 58 >> 1) begin
            num_operands = 1;
        end     
        // else if
           
    end
        
    if (format == `FORMAT_A || format == `FORMAT_E) begin
        if (instruction_in[`MASK] != 7) mask_used = 1;     // a mask register is used
    end
    
    
    // *** detect use of registers and pointer, index, scale factor, offset, limit, fallback ***
    index_limit = 0;
    offset_field = `OFFSET_NONE;
    immediate_field = `IMMED_NONE;
    rs_status = `REG_UNUSED;
    rt_status = `REG_UNUSED;
    rd_status = `REG_UNUSED;
    scale_factor = `SCALE_UNDEF;
    broadcast = 0;
    fallback_use = mask_used ? `FALLBACK_SOURCE : `FALLBACK_NONE;
    
    
    // ****** detect format ******
    if (il == 0) begin // format 0.x
        if ((mode == 0 && !M) || mode == 2) begin
            // format 0.0A, 0.2A: RD = f3(RD, RS, RT)
            if (num_operands > 0) rt_status = register_type;
            if (num_operands > 1 || mask_used) rs_status = register_type;
            if (num_operands > 2) rd_status = register_type;
            if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RS;
        end else if ((mode == 1 && !M) || mode == 3) begin
            // format 0.1B, 0.3B: RD = f3(RD, RS, IM1).
            if (num_operands > 1) rs_status = register_type;
            if (num_operands > 2) rd_status = register_type;
            immediate_field = `IMMED_1;            
        end else if (mode == 4) begin
            // format 0.4A: RD = f2(RD, [RS]).
            if (num_operands > 1 || mask_used) rd_status = `REG_VECTOR;
            if (num_operands > 2) format_error = 1;
            rs_status = `REG_POINTER; 
            rt_status = `REG_LENGTH; 
        end else if (mode == 5) begin
            // format 0.5A: f2(RD, [RS-RT]).
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_MINUS;
            if (num_operands > 1 || mask_used) rd_status = `REG_VECTOR;
            if (num_operands > 2) format_error = 1; 
        end else if (mode == 6) begin
            // format 0.6A: f2(RD, [RS+RT*OS]). scalar
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_OS; 
            if (num_operands > 1 || mask_used) rd_status = `REG_VECTOR;
            if (num_operands > 2) format_error = 1; 
        end else if (mode == 7) begin
            // format 0.7B: f2(RD, [RS+IM1*OS]). scalar
            rs_status = `REG_POINTER;
            scale_factor = `SCALE_OS;
            offset_field = `OFFSET_1;
            if (num_operands > 1) rd_status = `REG_VECTOR;
            if (num_operands > 2) format_error = 1; 
        end else if (mode == 0 && M) begin
            // format 0.8A: f2(RD, [RS+RT*OS]).
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_OS;
            if (num_operands > 1 || mask_used) rd_status = `REG_OPERAND;
            if (num_operands > 2) format_error = 1;
        end else if (mode == 1 && M) begin
            // format 0.9B: f2(RD, [RS+IM1*OS]).
            rs_status = `REG_POINTER;
            scale_factor = `SCALE_OS;
            offset_field = `OFFSET_1;
            if (num_operands > 1) rd_status = `REG_OPERAND;
            if (num_operands > 2) format_error = 1; 
        end
        
    end else if (il == 1) begin
        // format 1.x. no memory operands
        if ((mode == 0 && !M) || mode == 2) begin
            // format 1.0A, 1.2A: RD = f3(RD, RS, RT).
            if (num_operands > 0) rt_status = register_type;
            if (num_operands > 1 || mask_used) rs_status = register_type;
            if (num_operands > 2) rd_status = register_type;            
            if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RS;            
        end else if (mode == 1 || mode == 4) begin
            // format 1.1C, 1.4C: RD = f2(RD, IM1-2).
            if (num_operands > 1) rd_status = register_type;
            if (num_operands > 2) format_error = 1;
            immediate_field = `IMMED_2; 
        end else if (mode == 3 || (mode == 0 & M)) begin
            // format 1.3B, 1.8B: RD = f3(RD, RS, IM1). 
            if (num_operands > 1) rs_status = register_type;
            if (num_operands > 2) rd_status = register_type;
            if (op1 == `II_READ_SPEC18 && mode[0] == 0) rs_status = `REG_SYSTEM;
            immediate_field = `IMMED_1;
        end else if (mode == 4) begin
            // format 1.4C: RD = f2(RD, IM1-2) 
            immediate_field = `IMMED_2;
            if (num_operands > 1) rd_status = register_type;
        end else if (mode == 5) begin
            // format 1.5: 
            format_error = 1;                              // format 1.5 unused
        end else if (mode == 6) begin
            // format 1.6: jump instructions
            if (op1 <= `IJ_LAST_CONDITIONAL) begin
                // ordinary conditional jumps
                rs_status = register_type;
                rd_status = register_type;
            end else if (op1[5:1] == (`IJ_JUMP_INDIRECT_MEM >> 1)) begin
                // indirect jump to memory address
                rs_status = `REG_POINTER;
                offset_field = `OFFSET_1; 
                scale_factor = `SCALE_OS;  
            end else if (op1[5:1] == (`IJ_JUMP_RELATIVE >> 1)) begin
                // jump to table of relative pointers in memory. format 1.6A
                rs_status = `REG_POINTER;
                if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
                rd_status = `REG_OPERAND;
                scale_factor = `SCALE_OS;
                offset_field = `OFFSET_NONE;
                if (instruction_in[`MASK] != 7) format_error = 1; // mask not allowed
            end else if (op1 == `IJ_SYSCALL) begin
                rs_status = `REG_OPERAND;
                rt_status = `REG_OPERAND;
                rd_status = `REG_OPERAND;            
            end
        end else if (mode == 7) begin
            // format 1.7: jump instructions
            if (op1 != `IJ_SYSRETURN && op1 != `IJ_TRAP) begin
                rd_status = register_type;            
            end
            if (op1 <= `IJ_LAST_CONDITIONAL) begin
                immediate_field = `IMMED_1;                // IM2 = immediate operand
            end
        end else if (mode == 0 && M) begin
            // format 1.8B: RD = f3(RD, RS, IM1).
            if (num_operands > 0) rs_status = `REG_OPERAND;
            if (num_operands > 1) rd_status = `REG_OPERAND;
            if (num_operands > 2) format_error = 1;
            immediate_field = `IMMED_1;
        end
        
    end else if (il == 2 && mode == 0 && !M) begin
        // format 2.0.x E
        if (mode2 == 0) begin
            // format 2.0.0: RD = f3(RU, RT, [RS+IM4]).
            rs_status = `REG_POINTER;
            offset_field = `OFFSET_2;
            if (num_operands > 1) rt_status = `REG_OPERAND;
            if (num_operands > 2 | mask_used | mask_alternative) ru_status = `REG_OPERAND;            
            if ((mask_used | mask_alternative) && num_operands < 3) fallback_use = `FALLBACK_RU;            
        end else if (mode2 == 1) begin
            // format 2.0.1: RD = f3(RD, RU, [RS+RT+IM4]).
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            offset_field = `OFFSET_2;
            scale_factor = `SCALE_NONE; 
            if (num_operands > 1 || mask_used) ru_status = `REG_OPERAND;
            if (num_operands > 2) rd_status = `REG_OPERAND;
            if (mask_used && num_operands == 1) begin
                fallback_use = `FALLBACK_RU;  ru_status = `REG_OPERAND;
            end
        end else if (mode2 == 2) begin
            // format 2.0.2: RD = f3(RD, RU, [RS+RT*OS+IM4]).
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            offset_field = `OFFSET_2;
            scale_factor = `SCALE_OS;  
            if (num_operands > 1 || mask_used) ru_status = `REG_OPERAND;
            if (num_operands > 2) rd_status = `REG_OPERAND;
            if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RU;
        end else if (mode2 == 3) begin
            // format 2.0.3: RD = f3(RD, RU, [RS+RT*OS]).. limit IM4
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_OS;
            index_limit = 1;
            if (num_operands > 1 || mask_used) ru_status = `REG_OPERAND;
            if (num_operands > 2) rd_status = `REG_OPERAND;            
            if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RU;
        end else if (mode2 == 5) begin
            // format 2.0.5: RD = f3(RU, [RS+RT*OS+IM4], IM5).
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_OS;
            offset_field = `OFFSET_2;
            immediate_field = `IMMED_1;                    // immediate field IM5 extended into OP2
            if (num_operands > 2 | mask_used | mask_alternative) ru_status = `REG_OPERAND;
            if ((mask_used | mask_alternative) && num_operands < 3) fallback_use = `FALLBACK_RU;            
        end else if (mode2 == 6) begin
            offset_field = `OFFSET_NONE;
            // format 2.0.6: RD = f3(RU, RS, RT).
            rt_status = `REG_OPERAND;
            if (num_operands > 1) rs_status = `REG_OPERAND;
            if (num_operands > 2 | mask_used | mask_alternative) ru_status = `REG_OPERAND;
            if ((mask_used | mask_alternative) && num_operands < 3) fallback_use = `FALLBACK_RU;            
        end else if (mode2 == 7) begin
            immediate_field = `IMMED_2;
            // format 2.0.7: RD = f3(RS, RT, IM4 << IM5).
            if (num_operands > 1) rt_status = `REG_OPERAND;
            if (num_operands > 2) rs_status = `REG_OPERAND;
            if ((mask_used | mask_alternative) && num_operands < 3) begin
                fallback_use = `FALLBACK_RS;  rs_status = `REG_OPERAND;
            end
        end else begin
            // format 2.0.4 unused      
            format_error = 1;
        end
        
    end else if (il == 2 && mode == 1 && !M) begin
        // format 2.1A. RD = f3(RD, RT, [RS+IM6]).
        rs_status = `REG_POINTER;
        offset_field = `OFFSET_3;
        scale_factor = `SCALE_NONE;
        if (num_operands > 1 || mask_used) rt_status = `REG_OPERAND;
        if (num_operands > 2) rd_status = `REG_OPERAND;
        if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RT;
        
    end else if (il == 2 && mode == 2) begin
        // format 2.2.x E
        if (mode2 == 0) begin
            // format 2.2.0: RD = f3(RD, RU, [RS+IM4]). broadcast
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_LENGTH;
            offset_field = `OFFSET_2;
            broadcast = 1;
            if (num_operands > 1 || mask_used) ru_status = `REG_VECTOR;
            if (num_operands > 2) rd_status = `REG_VECTOR;
            if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RU;
        end else if (mode2 == 1) begin
            // format 2.2.1: RD = f3(RD, RU, [RS+IM4]). length RT
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_LENGTH;
            offset_field = `OFFSET_2;
            if (num_operands > 1 || mask_used) ru_status = `REG_VECTOR;
            if (num_operands > 2) rd_status = `REG_VECTOR;
            if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RU; 
        end else if (mode2 == 2) begin
            // format 2.2.2: RD = f3(RD, RU, [RS+RT*OS+IM4]).. scalar
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            offset_field = `OFFSET_2;
            scale_factor = `SCALE_OS;            
            if (num_operands > 1 || mask_used) ru_status = `REG_VECTOR;
            if (num_operands > 2) rd_status = `REG_VECTOR;
            if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RU; 
        end else if (mode2 == 3) begin
            // format 2.2.3: RD = f3(RD, RU, [RS+RT*OS]).. limit IM4
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_OS;
            index_limit = 1;            
            if (num_operands > 1 || mask_used) ru_status = `REG_VECTOR;
            if (num_operands > 2) rd_status = `REG_VECTOR;
            if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RU;
        end else if (mode2 == 4) begin
            // format 2.2.4: RD = f3(RD, RU, [RS-RT+IM4]).
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_MINUS;
            offset_field = `OFFSET_2;
            if (num_operands > 1 || mask_used) ru_status = `REG_VECTOR;
            if (num_operands > 2) rd_status = `REG_VECTOR;                    
            if (mask_used && num_operands == 1) fallback_use = `FALLBACK_RU;
        end else if (mode2 == 5) begin
            // format 2.2.5: RD = f3(RU, [RS+IM4], IM5).        
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_LENGTH;
            offset_field = `OFFSET_2;
            immediate_field = `IMMED_1;                    // immediate field IM5 extended into OP2
            if (num_operands > 2 || mask_used) ru_status = `REG_OPERAND;
            if ((mask_used | mask_alternative) && num_operands < 3) begin
                fallback_use = `FALLBACK_RU;  ru_status = `REG_VECTOR;
            end
        end else if (mode2 == 6) begin
            // format 2.2.6: RD = f3(RU, RS, RT).
            offset_field = `OFFSET_NONE;                   // register operands only
            rt_status = `REG_VECTOR;
            if (num_operands > 1) rs_status = `REG_VECTOR;
            if (num_operands > 2) ru_status = `REG_VECTOR;
            if ((mask_used | mask_alternative) && num_operands < 3) begin
                fallback_use = `FALLBACK_RU; ru_status = `REG_VECTOR;
            end
        end else if (mode2 == 7) begin
            // format 2.2.7: RD = f3(RS, RT, IM4 << IM5).
            immediate_field = `IMMED_2;                    // immediate operand 
            if (num_operands > 1) rt_status = `REG_VECTOR;
            if (num_operands > 2) rs_status = `REG_VECTOR;
            if ((mask_used | mask_alternative) && num_operands < 3) begin
                fallback_use = `FALLBACK_RS;  rs_status = `REG_VECTOR;
            end
        end
        
    end else if (il == 2 && mode == 3) begin
        // format 2.3A: RD = f3(RS, RT, IM6).
        immediate_field = `IMMED_3;                        // immediate operand
        if (num_operands > 1) rt_status = `REG_VECTOR;
        if (num_operands > 2 || mask_used) rs_status = `REG_VECTOR;
        if (mask_used && num_operands < 3)  fallback_use = `FALLBACK_RS;
        
    end else if (il == 2 && mode == 4) begin
        // format 2.4A: RD = f2(RD, [RS+IM6]). length=RT.
        rs_status = `REG_POINTER;
        if (instruction_in[`RT] != 5'H1F) rt_status = `REG_LENGTH;
        offset_field = `OFFSET_3;
        if (num_operands > 1 || mask_used) rd_status = `REG_VECTOR;
        if (num_operands > 2) format_error = 1;
        
    end else if (il == 2 && mode == 5) begin
        // format 2.5: jump or mixed    
        if (op1 < 8) begin                                 // jump instructions. Detect number of operands
            if (op1 == 2 && instruction_in[5:1] == `IJ_JUMP_INDIRECT_MEM >> 1) num_operands = 1;
        end    
        if (op1 == 0) begin
            // format 2.5.0A: jump with three register operands and 24 bit offset
            rs_status = register_type;
            rt_status = register_type;
        end else if (op1 == 1) begin
            // format 2.5.1B: jump with a register source operand and a 16-bit immediate operand
            rs_status = register_type;
            immediate_field = `IMMED_2;                    // 16 bit in lower half of IM6            
        end else if (op1 == 2) begin
            // format 2.5.2B: jump with register (RD), memory operand w 16 bit address, 16 bit jump offset 
            rd_status = register_type;
            rs_status = `REG_POINTER;
            offset_field = `OFFSET_2;
            if (instruction_in[5:1] == `IJ_JUMP_INDIRECT_MEM >> 1) offset_field = `OFFSET_3; // format 2.5.2x: 32 bit memory offset
        end else if (op1 == 3) begin
            // format 2.5.3: unused
            format_error = 1;
        end else if (op1 == 4) begin
            // format 2.5.4: jump with register (RD), one 8-bit immediate constant and 32 bit offset
            rd_status = register_type;
            immediate_field = `IMMED_1;                    // note: immediate operand in bit 8-15            
        end else if (op1 == 5) begin
            // format 2.5.5: jump with one register operand (RD), an 8-bit offset and a 32-bit immediate constant
            rd_status = register_type;
            immediate_field = `IMMED_3;
        end else if (op1 == 6) begin
            // format 2.5.6: unused
            format_error = 1;
        end else if (op1 == 7) begin
            // format 2.5.7: system call, no OPJ, 16 bit constant and 32-bit constant
            rd_status = `REG_OPERAND;
            immediate_field = `IMMED_3;            
        end else if (op1 == `II_STOREI) begin              // store constant to memory 
            rs_status = `REG_POINTER;
            offset_field = `OFFSET_1;
            immediate_field = `IMMED_3;
        end else if (op1 == `II_CMPSWAP) begin             // compare_swap instruction not implemented
            rs_status = `REG_POINTER;
            rt_status = `REG_OPERAND;
            rd_status = `REG_OPERAND;
            offset_field = `OFFSET_3;
        end else begin                                     // other. mixed format. fallback use unknown          
            rs_status = `REG_POINTER;
            offset_field = `OFFSET_3;
            rt_status = register_type;
            rd_status = register_type;
        end        
        
    end else if (il == 2 && mode == 6) begin
        // format 2.6A: RD = f3(RS, RT, IM6).
        immediate_field = `IMMED_3;
        if (num_operands > 1) rt_status = `REG_VECTOR;
        if (num_operands > 2 || mask_used) rs_status = `REG_VECTOR;
        if (mask_used && num_operands < 3)  fallback_use = `FALLBACK_RS;

    end else if (il == 2 && mode == 7) begin
        // format 2.7: unused
        format_error = 1;
        
    end else if (il == 2 && mode == 0 && M) begin
        // format 2.8A: RD = f3(RS, RT, IM6).
        immediate_field = `IMMED_3;    
        if (num_operands > 1) rt_status = `REG_OPERAND;
        if (num_operands > 2 || mask_used) rs_status = `REG_OPERAND;
        if (mask_used && num_operands < 3) begin
            fallback_use = `FALLBACK_RS;
        end
        
    end else if (il == 2 && mode == 1 && M) begin
        // format 2.9A: RD = f3(RS, RT, IM6).
        if (op1 == `II_ADDRESS_29) begin
            offset_field = `OFFSET_3;                      // address instruction
            rs_status = `REG_POINTER;
            if (mask_used) fallback_use = `FALLBACK_RT;    // can address instruction have mask?
            if (mask_used) rt_status = `REG_OPERAND;
                    
        end else begin
            immediate_field = `IMMED_3;
            if (num_operands > 1) rt_status = `REG_OPERAND;
            if (num_operands > 2 || mask_used) rs_status = `REG_OPERAND;        
            if (mask_used && num_operands < 3) fallback_use = `FALLBACK_RS;
        end
        
    end else if (il == 3 && mode == 0 && !M) begin
        // format 3.0.x E
        if (mode2 == 0) begin
            // format 3.0.0: RD = f3(RU, RS, [RS+IM7]).
            rs_status = `REG_POINTER;
            offset_field = `OFFSET_3;
            if (num_operands > 1) rt_status = `REG_OPERAND;
            if (num_operands > 2) ru_status = `REG_OPERAND;
            if ((mask_used | mask_alternative) && num_operands < 3) begin
                fallback_use = `FALLBACK_RU;  ru_status = `REG_OPERAND;
            end
        end else if (mode2 == 2) begin
            // format 3.0.2: RD = f3(RD, RU, [RS+RT*OS+IM7]).
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            offset_field = `OFFSET_3;
            scale_factor = `SCALE_OS;
            if (num_operands > 1 || mask_used) ru_status = `REG_OPERAND;
            if (num_operands > 2) rd_status = `REG_OPERAND;
            if (mask_used && num_operands == 1) begin
                fallback_use = `FALLBACK_RU;
            end
        end else if (mode2 == 3) begin
            // format 3.0.3: RD = f3(RD, RU, [RS+RT*OS]).. limit IM7
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_OS;
            index_limit = 1;
            if (num_operands > 1 || mask_used) ru_status = `REG_OPERAND;
            if (num_operands > 2) rd_status = `REG_OPERAND;            
            if (mask_used && num_operands == 1) begin
                fallback_use = `FALLBACK_RU;
            end
        end else if (mode2 == 5) begin
            // format 3.0.5: RD = f3(RU, [RS+RT*OS+IM4], IM7).         
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_OS;
            offset_field = `OFFSET_2;
            immediate_field = `IMMED_3;
            if (num_operands > 2) ru_status = `REG_OPERAND;            
            if ((mask_used | mask_alternative) && num_operands < 3) begin
                fallback_use = `FALLBACK_RU; ru_status = `REG_OPERAND;
            end
        end else if (mode2 == 7) begin
            // format 3.0.7: RD = f3(RS, RT, IM7 << IM4).         
            immediate_field = `IMMED_3;
            if (num_operands > 1) rt_status = `REG_OPERAND;
            if (num_operands > 2 || mask_used) rs_status = `REG_OPERAND;
            if ((mask_used | mask_alternative) && num_operands < 3) begin
                fallback_use = `FALLBACK_RS; rs_status = `REG_OPERAND;
            end
        end else begin
            format_error = 1;                              // other formats unused      
        end
                    
    end else if (il == 3 && mode == 1) begin
        // format 3.1: jump or mixed    
        if (op1 < 8) begin 
            // jump instructions. Detect number of operands
            if (op1 == 1 && instruction_in[5:1] == `IJ_JUMP_DIRECT >> 1) num_operands = 0; // direct jump
        end
    
        if (op1 == 0) begin 
            // format 3.1.0A jump with two registers, memory operand with 32 bit address, 24 bit jump offset
            rs_status = `REG_POINTER;
            rt_status = register_type;
            offset_field = `OFFSET_3;
        end else if (op1 == 1) begin 
            // format 3.1.1B: jump with 2 registers, 32-bit immediate operand and a 32-bit jump offset
            rs_status = register_type;
            immediate_field = `IMMED_3;

        end else begin 
            // single format instructions in format 3.1
            immediate_field = `IMMED_3;
            if (num_operands > 0) rt_status = register_type;
            if (num_operands > 1 || mask_used) rs_status = register_type;
            if (num_operands > 2) rd_status = register_type;
            // mixed formats. fallback use unknown
        end
        
    end else if (il == 3 && mode == 2) begin
        // format 3.2.x E
        if (mode2 == 0) begin 
            // format 3.2.0: RD = f3(RD, RU, [RS+IM7]).. broadcast
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_LENGTH;
            offset_field = `OFFSET_3;
            broadcast = 1;
            if (num_operands > 1 || mask_used) ru_status = `REG_VECTOR;
            if (num_operands > 2) rd_status = `REG_VECTOR;
            if (mask_used && num_operands == 1) begin
                fallback_use = `FALLBACK_RU;
            end
        end else if (mode2 == 1) begin 
            // format 3.2.1: RD = f3(RD, RU, [RS+IM7]). Length RT
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_LENGTH;
            offset_field = `OFFSET_3;
            if (num_operands > 1 || mask_used) ru_status = `REG_VECTOR;
            if (num_operands > 2) rd_status = `REG_VECTOR;
            if (mask_used && num_operands == 1) begin
                fallback_use = `FALLBACK_RU;
            end
        end else if (mode2 == 2) begin 
            // format 3.2.2: RD = f3(RD, RU, [RS+RT*OS+IM7]).. scalar
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            offset_field = `OFFSET_3;
            scale_factor = `SCALE_OS;
            if (num_operands > 1 || mask_used) ru_status = `REG_VECTOR;
            if (num_operands > 2) rd_status = `REG_VECTOR;
            if (mask_used && num_operands == 1) begin
                fallback_use = `FALLBACK_RU;
            end
        end else if (mode2 == 3) begin 
            // format 3.2.3: RD = f3(RD, RU, [RS+RT*OS]).. limit IM7
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_INDEX;
            scale_factor = `SCALE_OS;
            index_limit = 1;
            if (num_operands > 1 || mask_used) ru_status = `REG_VECTOR;
            if (num_operands > 2) rd_status = `REG_VECTOR;            
            if (mask_used && num_operands == 1) begin
                fallback_use = `FALLBACK_RU;
            end
        end else if (mode2 == 5) begin 
            // format 3.2.5: RD = f3(RU, [RS+IM4], IM7). Length=RT.
            rs_status = `REG_POINTER;
            if (instruction_in[`RT] != 5'H1F) rt_status = `REG_LENGTH;
            offset_field = `OFFSET_2;
            immediate_field = `IMMED_3;
            if (num_operands > 2 || mask_used) ru_status = `REG_VECTOR;            
            if ((mask_used | mask_alternative) && num_operands < 3) begin
                fallback_use = `FALLBACK_RU;  ru_status = `REG_VECTOR;
            end
        end else if (mode2 == 7) begin 
            // format 3.2.7: RD = f3(RS, RT, IM7).
            immediate_field = `IMMED_3;
            if (num_operands > 1) rt_status = `REG_VECTOR;
            if (num_operands > 2 || mask_used) rs_status = `REG_VECTOR;
            if ((mask_used | mask_alternative) && num_operands < 3) begin
                fallback_use = `FALLBACK_RS;  rs_status = `REG_VECTOR;
            end
        end else begin
            // other formats unused      
            format_error = 1;   
        end
        
    end else if (il == 3 && mode == 3) begin 
        // format 3.3A: RD = f3(RS, RT, IM6-7).
        immediate_field = `IMMED_3;
        if (num_operands > 1) rt_status = `REG_VECTOR;
        if (num_operands > 2 || mask_used) rs_status = `REG_VECTOR;
        if (mask_used && num_operands < 3) fallback_use = `FALLBACK_RS;
    end else if (il == 3 && mode == 0 && M) begin 
        // format 3.8A: RD = f3(RS, RT, IM6-7).
        immediate_field = `IMMED_3;
        if (num_operands > 1) rt_status = `REG_OPERAND;
        if (num_operands > 2 || mask_used) rs_status = `REG_OPERAND;
        if (mask_used && num_operands < 3) fallback_use = `FALLBACK_RS;
    end
    
    
    // ****** detect type of result ******
    result_type = `RESULT_REG;                             // default result type
    if (category == `CAT_MULTI && op1 == `II_STORE) begin
        result_type = `RESULT_MEM;                         // store instruction
        rd_status = `REG_OPERAND;                          // source is rd        
    end else if (il == 2 && mode == 5 &&
        (op1 == `II_STOREI || op1 == `II_FENCE || op1 == `II_CMPSWAP || op1 == `II_XTR_STORE)) begin
        result_type = `RESULT_MEM;                         // various complex memory instructions       
    end else if (il == 1 && mode == 0 && M &&              // format 1.8
        (op1 == `II_WR_SPEC || op1 == `II_WR_CAPA)) begin
        result_type = `RESULT_SYS;                         // write system registers
    end else if (il == 1 && mode == 0 && M && op1 == `II_OUTPUT_18) begin
        result_type = `RESULT_NONE;                        // output, format 1.8
    end else if (category == `CAT_MULTI & (op1 == `II_NOP | op1 == `II_PREFETCH)) begin
        result_type = `RESULT_NONE;                        // nop        
    end else if (il == 1 && mode == 2 && op1 == `II_OUTPUT_18) begin
        result_type = `RESULT_NONE;                        // output, format 1.2
    end else if (il == 1 && mode == 3 && op1 == `II_CLEAR) begin
        result_type = `RESULT_NONE;                        // the clear instruction goes directly to the vector register file, not through the ALU
    end else if (category == `CAT_JUMP && il == 1) begin
        if ((op1 <= `II_UNCOND_JUMP && mode == 7) || (op1 >= `II_COMPARE_FIRST && op1 <= `II_COMPARE_LAST) || op1 >= `II_INDIRECT_JUMP) result_type = `RESULT_NONE;
    end else if (category == `CAT_JUMP && il > 1 && op1 == 0) begin // jump formats 2.5.0A and 3.1.0A have opj in byte 7    
        if ((instruction_in[61:56] >= `II_COMPARE_FIRST && instruction_in[61:56] <= `II_COMPARE_LAST) || instruction_in[61:56] >= `II_INDIRECT_JUMP) result_type = `RESULT_NONE;         
    end else if (category == `CAT_JUMP && il > 1) begin    // other jump formats have opj in byte 0
        if ((instruction_in[5:0] >= `II_COMPARE_FIRST && instruction_in[5:0] <= `II_COMPARE_LAST) || instruction_in[5:0] >= `II_INDIRECT_JUMP) result_type = `RESULT_NONE; 
    end
end


//  ***********  Decode instructions that generate multiple micro-ops  ***********
always_comb begin
    push_instruction = il == 1 & op1 == 56 & ((mode == 0 & M) | mode == 3); // push instruction generated
    pop_instruction  = il == 1 & op1 == 57 & ((mode == 0 & M) | mode == 3); // pop instruction generated
    case (instruction_in[`OT2])   // determine address increment or decrement
        0: pop_increment = 1;
        1: pop_increment = 2;
        2: pop_increment = 4;
        3: pop_increment = 8;
    endcase
    
    decrement_before = push_instruction & !instruction_in[7]; // decrement pointer first, then write
    increment_after = pop_instruction | (push_instruction & instruction_in[7]); // increment pointer after
    reverse_register_order = pop_instruction & !instruction_in[6]; // pop last register first
    multi_first = (push_instruction | pop_instruction) & !multi_op; // first cycle of multi instruction
    multi_last = multi_op & !reverse_register_order & instruction_out[`RD] == instruction_in[`RT]
    | multi_op & reverse_register_order & instruction_out[`RD] == instruction_in[`RS];
    
    multi_last_next = multi_first & instruction_in[`RT] == instruction_in[`RS]
    | multi_op & !reverse_register_order & instruction_out[`RD] == instruction_in[`RT] - 1
    | multi_op & reverse_register_order & instruction_out[`RD] == instruction_in[`RS] + 1;
    
    push_pop_error = multi_first & instruction_in[`RT] < instruction_in[`RS]
    | multi_op & instruction_out[`RD] == instruction_out[`RS];
end


// *** update tags ***
// All instructions need a tag in order to distinguish instructions
always_comb begin
    max_tag = ~(`TAG_WIDTH'b0);   // maximum tag is all ones (5'b11111)
    
    // next possible tag value
    next1 = current_tag + 1;
    next2 = current_tag + 2;
    next3 = current_tag + 3;
    // skip tag value 0:
    if (current_tag == max_tag) begin
        next1 = 1;
        next2 = 2;
        next3 = 3;
    end else if (current_tag == max_tag - 1) begin 
        next2 = 1;
        next3 = 2;
    end else if (current_tag == max_tag - 2) begin 
        next3 = 1;
    end
    
    /* A tag value may be occupied by a long-latency instruction started in a previous cycle.
    This code will skip an occupied tag value. Two consecutive occupied tag values will cause
    a stall until one tag is freed. This can only happen if two long-latency instructions are
    executed in parallel. e.g integer division and vector division happening in parallel.
    */
    if (valid_in | multi_op) begin
        next_tag = next1;
        next_next_tag = next2;
        // skip tag values that are occupied 
        if (tag_used[next1]) begin
            next_tag = next2;
            next_next_tag = next3;
        end else if (tag_used[next2]) begin
            next_next_tag = next3;
        end
    end else begin
        next_tag = 0;
        next_next_tag = 0;
    end
end


// ****** update list of tags in use ******
genvar i;   // generation loop for all bits in tag_used    
for (i=0; i < (2**`TAG_WIDTH); i++) begin
    //always_ff @(posedge clock) if (clock_enable && !stall_in) begin
    always_ff @(posedge clock) if (clock_enable) begin
        if (reset) begin
            tag_used[i] <= 0;
        end else if (i == current_tag) begin
            tag_used[i] <= 1;
        end else if (i == write_tag1 | i == write_tag2) begin
            tag_used[i] <= 0;
        end
    end
end
   
    
// ******      outputs      ******

always_ff @(posedge clock) if (clock_enable) begin
    if (reset) valid_out <= 0;
    else if (!stall_in) valid_out <= valid_in | multi_op;    
    multi_finish_out <= 0;
    
    // send tag to register file
    if ((valid_in | multi_op) & !stall_in & !reset) begin
        // tag_write_out done below
        tag_a_out <= {result_type[0], instruction_in[`RD]};
        tag_val_out <= current_tag;        
        current_tag <= next_tag;  // update current tag      
    end        

    // predict if a tag is not available in next clock cycle
    if (tag_used[next_tag] | tag_used[next_next_tag]) begin
        stall_predict_out <= 1;
    end else begin
        stall_predict_out <= 0;
    end 
    
    // *** output instruction code ***
    if (!stall_in) begin
        if (!multi_op) begin
            instruction_pointer_out <= instruction_pointer_in;
            instruction_out <= instruction_in;
            vector_out <= register_type == `REG_VECTOR;
            category_out <= category;
            format_out <= format;
            rs_status_out <= rs_status;
            rt_status_out <= rt_status;
            ru_status_out <= ru_status;
            rd_status_out <= rd_status;
            mask_status_out <= (mask_used || mask_options) ? register_type : `REG_UNUSED;
            mask_options_out <= mask_options;
            mask_alternative_out <= mask_alternative;
            fallback_use_out <= fallback_use;
            num_operands_out <= num_operands;
            result_type_out <= result_type;
            offset_field_out <= offset_field;
            immediate_field_out <= immediate_field;
            scale_factor_out <= scale_factor;
            index_limit_out <= index_limit;
            if (valid_in) begin
                tag_write_out <= result_type == `RESULT_REG || result_type == `RESULT_SYS;
            end else begin
                tag_write_out <= 0;            
            end            
        end

        // modify instruction_out if multi-op instruction
        if ((push_instruction | pop_instruction) & multi_first & instruction_pointer_in[2:0] != instruction_pointer_out[2:0]) begin  // generate read or write instruction
            multi_op <= 1;
            // make instruction for read/write register RD with pointer RS, offset IM4, format 2.0.0E
            instruction_out[`IL] <= 2;
            instruction_out[`MODE] <= 0;
            instruction_out[`MODE2] <= 0;
            instruction_out[`RD] <= reverse_register_order ? instruction_in[`RT] : instruction_in[`RS];
            instruction_out[`RS] <= instruction_in[`RD]; // stack pointer
            instruction_out[`OP2] <= 0;
            instruction_out[`IM4] <= decrement_before ? -pop_increment : 0;
            instruction_out[`M] <= 0;
            instruction_out[`MASK] <= 7;            
            category_out <= `CAT_MULTI;
            format_out <= `FORMAT_E;
            rs_status_out <= `REG_POINTER;
            rt_status_out <= `REG_UNUSED;
            ru_status_out <= `REG_UNUSED;
            rd_status_out <= `REG_OPERAND;
            num_operands_out <= 1;
            offset_field_out <= `OFFSET_2;
            immediate_field_out <= `IMMED_NONE;
            if (push_instruction) begin
                instruction_out[`OP1] <= `II_STORE;
                result_type_out <= `RESULT_MEM;
                tag_write_out <= 0;
            end else begin
                instruction_out[`OP1] <= `II_MOVE;
                result_type_out <= `RESULT_REG;
                tag_write_out <= 1;
            end
        end else if (multi_op & !multi_last) begin
            // increment or decrement address
            instruction_out[`IM4] <= decrement_before ? instruction_out[`IM4] - pop_increment : instruction_out[`IM4] + pop_increment;
            // increment or decrement register
            instruction_out[`RD] <= reverse_register_order ? instruction_out[`RD] - 1 : instruction_out[`RD] + 1;
        end else if (multi_last) begin
            // make instruction to add or subtract to stack pointer, format 2.0.7E
            instruction_out[`MODE2] <= 7;
            instruction_out[`RT] <= instruction_in[`RD];
            instruction_out[`RD] <= instruction_in[`RD];
            instruction_out[`OP1] <= `II_ADD;
            instruction_out[`OT] <= `OT_INT64;
            rs_status_out <= `REG_UNUSED;
            rt_status_out <= `REG_OPERAND;
            num_operands_out <= 2;
            result_type_out <= `RESULT_REG;
            tag_write_out <= 1;
            offset_field_out <= `OFFSET_NONE;
            immediate_field_out <= `IMMED_2;
            if (increment_after) begin
                // pointer offset in IM4 becomes addend. decrement_before has subtracted one time too many
                instruction_out[`IM4] <= instruction_out[`IM4] + pop_increment;
            end
            instruction_out[`IM5] <= 0;
            multi_op <= 0;
            //multi_finish_out <= 1;
        end        
        if ((multi_first | multi_op) & multi_last_next) multi_finish_out <= 1;
        error_out <= (format_error | push_pop_error) & valid_in;
    end
    
    if (reset) begin
        multi_op <= 0;
        current_tag <= 1;
    end
    
    
    // debug output
    debug1_out[3:0]   <= current_tag;
    debug1_out[7:4]   <= next_tag;
    debug1_out[11:8]  <= next_next_tag;
    debug1_out[12]    <= tag_used[next_tag] ;
    debug1_out[13]    <= tag_used[next_next_tag] ;
    
    debug1_out[16]    <= push_instruction;
    debug1_out[17]    <= pop_instruction;
    debug1_out[18]    <= 0;
    debug1_out[19]    <= push_pop_error;
    
    debug1_out[20]    <= multi_first;
    debug1_out[21]    <= multi_last;
    debug1_out[22]    <= multi_last_next;
    debug1_out[23]    <= multi_op;
    
    debug1_out[24]    <= decrement_before;
    debug1_out[25]    <= increment_after;
    debug1_out[26]    <= reverse_register_order;
    
    debug1_out[31:28] <= pop_increment;  
    
end

endmodule
