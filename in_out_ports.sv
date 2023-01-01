//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2020-11-16
// Last modified:  2022-12-08
// Module Name:    in_out_ports
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Input and output ports, as well as reading and writing of special 
// registers, including capabilities registers and performance counter registers 
//////////////////////////////////////////////////////////////////////////////////

/* Input and output ports:
All input and output bits beyond the specified operand size are set to zero.
The port address can have up to 64 bits regardless of the specified operand size.

The following input and output ports are currently defined:
-----------------------------------------------------------

RS232 serial input and output.
Transmission settings: 8 data bits, one stop bit, no parity, no flow control. 
The BAUD rate is currently defined in the file defines.vh

Input port 8. Serial input:
Read one byte from RS232 serial input. Non-blocking
The following value is returned:
bit 0-7: Received data (zero if input buffer empty)
bit   8: Data valid. Unreliable! 
bit   9: More data ready: The input buffer contains at least one more byte ready to read
bit  12: Buffer overflow error. Data has been lost due to input buffer overflow
bit  13: Frame error. Error detected in start bit or stop bit. May be due to noise or wrong BAUD rate

Input port 9. Serial input status:
bit 0-15: Number of bytes currently in input buffer
bit   16: Buffer overflow error. Data has been lost due to input buffer overflow
bit   17: Frame error. Error detected in start bit or stop bit. May be due to noise or wrong BAUD rate

Output port 9. Serial input control:
bit    0: Clear buffer. Delete all data currently in the input buffer, and clear error flags 
bit    1: Clear error flags but keep data. 
          The error bits remain high after an error condition until reset by this or by system reset 

Output port 10. Serial output:
Write one byte to RS232 serial output.
bit 0-7: Data to write
Other bits are reserved.

Input port 11. Serial output status:
bit 0-15: Number of bytes currently in output buffer
bit   16: Buffer overflow error. Data has been lost due to output buffer overflow
bit   18: Ready. The output buffer has enough space to receive at least one more byte

Output port 11. Serial output control:
bit    0: Clear buffer. Delete all data currently in the output buffer, and clear error flags 
bit    1: Clear error flags but keep data. 
The error bits remain high after an error condition until reset by this or by system reset 


The following special registers are currently defined:
-----------------------------------------------------------
Capabilities registers 0, 1, 4, 5
Performance counter registers 1 - 5, and 16

*/

`include "defines.vh"

module in_out_ports (
    input clock,                            // system clock
    input clock_enable,                     // clock enable. Used when single-stepping
    input reset,                            // system reset
    input valid_in,                         // data from previous stage ready
    input stall_in,                         // pipeline is stalled
    input [31:0] instruction_in,            // current instruction, up to 3 words long. Only first word used here
    input [`TAG_WIDTH-1:0] tag_val_in,      // instruction tag value    
    input [1:0]  category_in,               // 00: multiformat, 01: single format, 10: jump
    input [1:0]  result_type_in,            // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    input        mask_alternative_in,       // mask register used for alternative purposes    
    input        vector_in,                 // this is a vector instruction
    input [6:0]  opx_in,                    // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
    input [5:0]  opj_in,                    // operation ID for conditional jump instructions
    input [2:0]  ot_in,                     // operand type
    input        mask_used_in,           // mask register is used
    input uart_bit_in,                      // serial input
    //input uart_rts_in,                      // ready to send input (not used). Must add set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports uart_rts_in] to .xdc file if used
     
    // monitor result buses:
    input write_en1,                        // a result is written to writeport1
    input [`TAG_WIDTH-1:0] write_tag1_in,   // tag of result inwriteport1
    input [`RB1:0] writeport1_in,           // result bus 1
    input write_en2,                        // a result is written to writeport2
    input [`TAG_WIDTH-1:0] write_tag2_in,   // tag of result inwriteport2
    input [`RB1:0] writeport2_in,           // result bus 2
    input [`TAG_WIDTH-1:0] predict_tag1_in, // result tag value on writeport1 in next clock cycle
    input [`TAG_WIDTH-1:0] predict_tag2_in, // result tag value on writeport2 in next clock cycle
    
    // Register values sampled from result bus in previous stages
    input [`RB:0] operand1_in,              // first register operand RD or RU
    input [`RB:0] operand2_in,              // second register operand RS
    input [`RB:0] operand3_in,              // last register operand RT
    input [`MASKSZ:0] mask_val_in,          // mask register
    input         opr1_used_in,             // operand1_in is needed
    
    // signals used for performance monitoring and error detection
    input instruction_valid_in,             // instruction is valid but possibly going to a different exe unit
    input fast_jump_in,                     // a jump is bypassing the pipeline
    input [`N_ERROR_TYPES-1:0] errors_detect_in, // one bit for each type of error detected
    // instruction pointer at position of error
    input [`CODE_ADDR_WIDTH-1:0] fetch_instruction_pointer,
    input [`CODE_ADDR_WIDTH-1:0] dataread_instruction_pointer,
    input dataread_valid,                   // used when reconstructing alu_instruction_pointer
    input call_stack_overflow,              // used for differentiating errors_detect_in[1]
    input clear_error_in,                   // debugger clear error
       
    // outputs
    output reg valid_out,                   // for debug display: in_out is active
    output reg register_write_out, 
    output reg [5:0] register_a_out,        // register to write
    output reg [`RB1:0] result_out,         // value to write to register
    output reg [`TAG_WIDTH-1:0] tag_val_out,// instruction tag value
    output reg nojump_out,                  // serializing instruction finished
    output reg stall_out,                   // alu is waiting for an operand or not ready to receive a new instruction
    output reg stall_next_out,              // alu will be waiting in next clock cycle 
    output reg error_out,                   // unknown instruction
    output reg error_parm_out,              // wrong parameter for instruction
    output reg uart_bit_out,                // serial output
    output reg uart_cts_out,                // serial clear to send
    output reg [`N_ERROR_TYPES-1:0] capab_disable_errors, // capab2 register: disable errors
    output reg [3:0] first_error,           // error type for first error
    output reg [`CODE_ADDR_WIDTH-1:0] first_error_address, // code address of first error
    output reg [31:0] debug_out             // debug information        
);


logic [`RB1:0] operand1;                    // first register operand RD or RU. bit `RB is 1 if invalid 
logic [`RB1:0] operand2;                    // second register operand RS. bit `RB is 1 if invalid
logic [`RB1:0] operand3;                    // last register operand RT. bit `RB is 1 if invalid
logic [`MASKSZ:0] mask_val;                 // mask register
logic [1:0]  otout;                         // operand type for output
logic [`RB1:0] result;                      // result for output
logic [6:0]  opx;                           // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
logic [4:0] rs;                             // RS field in instruction
logic [4:0] rd;                             // RD field in instruction
logic stall;                                // waiting for operands
logic stall_next;                           // will be waiting for operands in next clock cycle
logic error;                                // unknown instruction
logic error_parm;                           // wrong parameter for instruction

logic [`RB1:0] port_address;                // address of input or output port

// submodules signals
reg UART_RX_receive_complete;
reg UART_RX_error;
reg [7:0] UART_RX_byte_out;
reg UART_TX_active;
reg UART_TX_tx_out;
reg UART_TX_done;

reg [7:0] fifo_buffer_input_byte;           // serial byte output prefetched
reg fifo_buffer_input_ready;                // the buffer contains at least one byte
reg fifo_buffer_input_overflow;             // attempt to write to full buffer
reg fifo_buffer_input_underflow;            // attempt to read from empty buffer
reg [`IN_BUFFER_SIZE_LOG2-1:0] fifo_buffer_input_num; // number of bytes currently in input buffer

reg [7:0] serial_output_byte_in;            // serial byte output 
reg [7:0] fifo_buffer_output_byte;          // serial byte output prefetched from buffer
reg fifo_buffer_output_ready;               // the buffer contains at least one byte
reg fifo_buffer_output_overflow;            // attempt to write to full buffer
reg fifo_buffer_output_underflow;           // attempt to read from empty buffer
reg [`OUT_BUFFER_SIZE_LOG2-1:0] fifo_buffer_output_num; // number of bytes currently in output buffer

logic fifo_buffer_input_read_next;
logic fifo_buffer_input_reset;
logic fifo_buffer_input_reset_error;
logic fifo_buffer_output_write;
logic fifo_buffer_output_reset;
logic fifo_buffer_output_reset_error;
logic mask_off;    

// temporary debug info
logic [31:0] debug_bits;

// performance counters
reg [`RB1:0] cpu_clock_cycles;              // count CPU clock cycles
reg [`RB1:0] num_instructions;              // count instructions
reg [`RB1:0] num_instructions_2size;        // count double size instructions
reg [`RB1:0] num_instructions_3size;        // count triple size instructions
reg [`RB1:0] num_instructions_gp;           // count instructions with g.p. registers
reg [`RB1:0] num_instructions_gp_mask0;     // count instructions with g.p. registers and mask = 0
reg [`RB1:0] num_instructions_vector;       // count instructions with vector registers
reg [`RB1:0] num_jump_call_return;          // count control transfer instructions
reg [`RB1:0] num_jump_call_direct;          // count direct unconditional jumps and calls
reg [`RB1:0] num_jump_call_indirect;        // count indirect jumps and calls
reg [`RB1:0] num_jump_conditional;          // count conditional jumps
reg [`RB1:0] num_unknown_instruction;       // count unknown instruction
reg [`RB1:0] num_wrong_operands;            // count wrong operands for instructions
reg [`RB1:0] num_array_overflow;            // count array index out of range
reg [`RB1:0] num_read_violation;            // count memory read access violation
reg [`RB1:0] num_write_violation;           // count memory write access violation
reg [`RB1:0] num_misaligned_memory;         // count misaligned memory access
reg          error_last;                    // error input was present in last clock cycle
reg          clock_enabled_last;            // clock was enabled in last clock cycle
reg          first_error_saved;             // an error has been detected and saved
reg [`CODE_ADDR_WIDTH-1:0] alu_instruction_pointer; // alu_instruction pointer is not input, but reconstructed here


// signals for resetting counters
logic reset_cpu_clock_cycles;
logic reset_num_instructions;
logic reset_num_instructions_vector;
logic reset_num_instructions_jump;
logic reset_num_errors;

always_comb begin
    // get all inputs
    stall = 0;
    stall_next = 0;
    debug_bits = 0;
    mask_off = 0;
    rs = instruction_in[`RS];
    rd = instruction_in[`RD];
    
    mask_val = 0;
    if (mask_val_in[`MASKSZ]) begin      // value missing
        if (write_en1 && mask_val_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            mask_val = writeport1_in;    // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && mask_val_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            mask_val = writeport2_in[(`MASKSZ-1):0]; // obtained from result bus 2
        end else begin
            if (mask_used_in & valid_in) begin
                stall = 1;                  // operand not ready
                if (mask_val_in[`TAG_WIDTH-1:0] != predict_tag1_in && mask_val_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                    stall_next = 1;         // operand not ready in next clock cycle
                end
            end                 
        end
    end else begin                          // value available
        mask_val = mask_val_in[(`MASKSZ-1):0];
    end    
        
    operand1 = 0;    
    if (operand1_in[`RB]) begin             // value missing
        if (operand1_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            operand1 = writeport1_in;       // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && operand1_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            operand1 = writeport2_in;       // obtained from result bus 2
        end else begin
            if (opr1_used_in & valid_in) begin
                stall = 1;                  // operand not ready
                debug_bits[0] = 1;
                if (operand1_in[`TAG_WIDTH-1:0] != predict_tag1_in && operand1_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                    stall_next = 1;         // operand not ready in next clock cycle
                    debug_bits[1] = 1;
                end                 
            end
        end
    end else begin
        operand1 = operand1_in[`RB1:0];
    end 

    operand2 = 0;
    if (operand2_in[`RB]) begin             // value missing
        if (operand2_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            operand2 = writeport1_in;       // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && operand2_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            operand2 =  writeport2_in;      // obtained from result bus 2
        end else begin
            stall = 1;                      // operand not ready
            debug_bits[2] = 1;            
            if (operand2_in[`TAG_WIDTH-1:0] != predict_tag1_in && operand2_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                stall_next = 1;             // operand not ready in next clock cycle
                debug_bits[3] = 1;                
            end                 
        end 
    end else begin                          // value available
        operand2 = operand2_in[`RB1:0];
    end

    // operand 3 is never missing if all instructions in this module have a constant as last operand:
    operand3 = operand3_in[`RB1:0];
    /*
    operand3 = 0;
    if (operand3_in[`RB]) begin // value missing
        if (operand3_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            operand3 = writeport1_in;  // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && operand3_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            operand3 =  writeport2_in; // obtained from result bus 2
        end else begin
            stall = 1; // operand not ready
            debug_bits[2] = 1;            
            if (operand3_in[`TAG_WIDTH-1:0] != predict_tag1_in && operand3_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                stall_next = 1; // operand not ready in next clock cycle
                debug_bits[3] = 1;                
            end                 
        end 
    end else begin // value available
        operand3 = operand3_in[`RB1:0];
    end*/
    
    mask_off = mask_used_in && mask_val[`MASKSZ] == 0 && mask_val[0] == 0 && !mask_alternative_in;
     
    opx = opx_in;                           // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
    otout = ot_in[1:0];                     // operand type for output
    error = 0;
    error_parm = 0;
    
    // get port address
    if (operand3 < 255) begin
        port_address = operand3;            // immediate address
    end else begin
        port_address = operand2;            // port address from register RS
    end
    
    
    ////////////////////////////////////////////////
    //             Select I/O operation
    ////////////////////////////////////////////////
    
    result = 0;
    fifo_buffer_input_read_next = 0;
    fifo_buffer_input_reset = 0;
    fifo_buffer_input_reset_error = 0;
    serial_output_byte_in = 0;
    fifo_buffer_output_write = 0;
    fifo_buffer_output_reset = 0;
    fifo_buffer_output_reset_error = 0;
    reset_cpu_clock_cycles = 0;
    reset_num_instructions = 0;
    reset_num_instructions_vector = 0;
    reset_num_instructions_jump = 0;
    reset_num_errors = 0;    
    
    if (valid_in && !stall && !stall_in) begin   
    
        if (opx == `IX_INPUT) begin
            // input port operation
            debug_bits[4] = 1;
            
            case (port_address)
            `INPORT_RS232: begin
                result[7:0] = fifo_buffer_input_byte;
                result[8] = fifo_buffer_input_ready;
                result[9] = fifo_buffer_input_num > 1;
                fifo_buffer_input_read_next = 1;
            end
            `INPORT_RS232_STATUS: begin
                if (`IN_BUFFER_SIZE_LOG2 > 16 && fifo_buffer_input_num >= 2**`IN_BUFFER_SIZE_LOG2) begin
                    result[15:0] = 16'HFFFF;
                end else begin
                    result[`IN_BUFFER_SIZE_LOG2-1:0] = fifo_buffer_input_num[`IN_BUFFER_SIZE_LOG2-1:0];
                end
                result[16] = fifo_buffer_input_overflow;
                result[17] = UART_RX_error;
            end
            `OUTPORT_RS232_STATUS: begin
                if (`OUT_BUFFER_SIZE_LOG2 > 16 && fifo_buffer_output_num >= 2**`OUT_BUFFER_SIZE_LOG2) begin
                    result[15:0] = 16'HFFFF;
                end else begin
                    result[`OUT_BUFFER_SIZE_LOG2-1:0] = fifo_buffer_output_num[`OUT_BUFFER_SIZE_LOG2-1:0];
                end
                result[16] = fifo_buffer_output_overflow;
                result[18] = ! (&fifo_buffer_output_num);
            end
            default: begin
                // unknown port address
                error_parm = 1;        
            end
            endcase      
          
        end else if (opx == `IX_OUTPUT) begin
        
            // output port operation
            debug_bits[5] = 1;
            case (port_address)
            `OUTPORT_RS232: begin
                serial_output_byte_in = operand1[7:0];
                fifo_buffer_output_write = 1;
            end
            `OUTPORT_RS232_STATUS: begin
                fifo_buffer_output_reset = operand1[0];
                fifo_buffer_output_reset_error = operand1[1];        
            end
            `INPORT_RS232_STATUS: begin
                fifo_buffer_input_reset = operand1[0];
                fifo_buffer_input_reset_error = operand1[1];
            end
            default: begin
                // unknown port address
                error_parm = 1;        
            end
            endcase
        
        end else if (opx == `IX_READ_CAPABILITIES) begin
            // read capabilities registers, etc.
            case (rs)
            0:  result = "A";                                 // Microprocessor brand ID 
            1:  result = 20'h10000;                           // Microprocessor version
            2:  result = capab_disable_errors;                // Capab2: disable error traps 
            4:  result = {1'b1,{(`CODE_ADDR_WIDTH+2){1'b0}}}; // Code memory size, (bytes)
            5:  result = {1'b1,{(`DATA_ADDR_WIDTH){1'b0}}};   // Data memory size, (bytes)
            8:  
            `ifdef SUPPORT_64BIT
                result = 4'b1111;                             // support for operand sizes
            `else
                result = 4'b0111;
            `endif 
            9:  result = `NUM_VECTOR_UNITS > 0 ? 4'b1111 : 0; // support for operand sizes in vectors
            12: result = `NUM_VECTOR_UNITS * 8;               // maximum vector length           
            13, 14, 15: result = `NUM_VECTOR_UNITS * 8;       // maximum vector length for permute, compress, expand, etc.           
            default: result = 0;
            endcase 
            
        end else if (opx == `IX_WRITE_CAPABILITIES) begin
            // write capabilities registers, etc.
            result = operand2;                                // any capabilities register written below
        
        end else if ((opx & -2) == `IX_READ_PERF) begin
            // read_perf and read_perfs
            case (rs)
            0:  begin  // reset all performance counters
                    reset_cpu_clock_cycles = operand3_in[0];
                    reset_num_instructions = operand3_in[1];
                    reset_num_instructions_vector = operand3_in[2];
                    reset_num_instructions_jump = operand3_in[3];
                    reset_num_errors = operand3_in[4];
                end
            1:  begin
                    result = cpu_clock_cycles;             // count CPU clock cycles
                    if (operand3_in[7:0] == 0) reset_cpu_clock_cycles = 1;
                end
            2:  begin                                      // count instructions
                case (operand3_in[7:0])
                0: begin
                       result = num_instructions;          // count instructions
                       reset_num_instructions = 1;
                   end
                1: result = num_instructions;              // count instructions
                2: result = num_instructions_2size;        // count double size instructions
                3: result = num_instructions_2size;        // count double size instructions
                4: result = num_instructions_gp;           // count instructions with g.p. registers
                5: result = num_instructions_gp_mask0;     // count instructions with g.p. registers and mask = 0
                endcase
                end
            3:  begin
                    result = num_instructions_vector;      // count instructions with vector registers
                    if (operand3_in[7:0] == 0) reset_num_instructions_vector = 1;                    
                end
            4:  result = 0;                                // vector registers in use
            5:  begin                                      // jump instructions
                case (operand3_in[7:0])
                0: begin
                       result = num_jump_call_return;      // count instructions
                       reset_num_instructions_jump = 1;
                   end
                1: result = num_jump_call_return;          // count control transfer instructions
                2: result = num_jump_call_direct;          // count direct unconditional jumps and calls
                3: result = num_jump_call_indirect;        // count indirect jumps and calls
                4: result = num_jump_conditional;          // count conditional jumps
                endcase            
                end
            16: begin                                      // count errors
                case (operand3_in[7:0])
                0: begin
                       reset_num_errors = 1;
                   end
                1:  result = num_unknown_instruction;
                2:  result = num_wrong_operands;     
                3:  result = num_array_overflow;     
                4:  result = num_read_violation;     
                5:  result = num_write_violation;
                6:  result = num_misaligned_memory;
                62: result = first_error;                  // error type for first error
                63: result = first_error_address;          // code address of first error
                endcase 
                end
            
            endcase       
        end else begin
            error = 1;                                     // unknown instruction
        end 
    end
    
    // output for debugger
    debug_bits[14:8] = opx;
    
    
    
    debug_bits[16] = stall;                  // waiting for operands
    debug_bits[17] = stall_next;             // will be waiting for operands in next clock cycle    
    debug_bits[19] = error;                  // unknown or illegal operation
    debug_bits[20] = valid_in;               // inout is enabled
    debug_bits[21] = fifo_buffer_input_read_next;
    debug_bits[22] = fifo_buffer_output_write;    
    //debug_bits[31:24] = port_address[7:0];
    debug_bits[31:24] = fifo_buffer_input_num;
    //debug_bits[15] = &instruction_in & ot_in[2] & operand3_in[`RB];         // avoid warning for unconnected input

    /*
    debug_bits[23:20] = error_number_in;
    debug_bits[31:24] = num_unknown_instruction[7:0];
    */

end


// output
always_ff @(posedge clock) if (clock_enable) begin
    if (!valid_in) begin
        register_write_out <= 0;
        // note: the FPGA has no internal tri-state buffers. We need to simulate result bus by or'ing outputs 
        result_out <= 0;
        register_a_out <= 0;

    // stall_in must disable the output to avoid executing the same instruction twice)
    end else if (stall || stall_in || result_type_in != `RESULT_REG) begin
        register_write_out <= 0;
        result_out <= 0;
        register_a_out <= 0;

    end else begin
        // register result from input instruction or read_capabilities, etc.
        case (otout)
        0: result_out <= result[7:0];
        1: result_out <= result[15:0];
        2: result_out <= result[31:0];
        3: result_out <= result[`RB1:0];
        endcase
        register_write_out <= ~reset;
        register_a_out <= {1'b0,rd};
    end
    
    if (valid_in & !stall) tag_val_out <= tag_val_in;
    else tag_val_out <= 0;
    
    
    if (result_type_in == `RESULT_SYS) begin
        // write system register
        if (opx == `IX_WRITE_CAPABILITIES && rd == 2) capab_disable_errors <= result;
    end
    if (reset) begin                                       // reset capabilities registers
        capab_disable_errors <= 0;    
    end    
    
    valid_out <= !stall & valid_in & !reset;
    stall_out <=  stall & valid_in & !reset;   
    stall_next_out <= stall_next & valid_in & !reset;    
    nojump_out <= (opx == `IX_READ_PERFS) & valid_in;      // resume after serializing
    error_out <= error & valid_in & !reset;                // unknown instruction   
    error_parm_out <= error_parm & valid_in & !reset;      // wrong parameter   
    uart_cts_out <= 1;                                     // UART clear to send
    debug_out <= debug_bits;                               // output for debugger
end


// update performance counters
always_ff @(posedge clock) if (clock_enable) begin
    cpu_clock_cycles <= cpu_clock_cycles + 1;
    if (instruction_valid_in) begin
        num_instructions <= num_instructions + 1 + fast_jump_in;
        if (instruction_in[`IL] == 2) num_instructions_2size <= num_instructions_2size + 1;
        if (instruction_in[`IL] == 3) num_instructions_3size <= num_instructions_3size + 1;
        if (vector_in) begin
            num_instructions_vector <= num_instructions_vector + 1;        
        end else begin
            num_instructions_gp <= num_instructions_gp + 1;
            if (mask_off) num_instructions_gp_mask0 <= num_instructions_gp_mask0 + 1;
        end
        if (category_in == `CAT_JUMP) begin                // jump instructions
            num_jump_call_return <= num_jump_call_return + 1 + fast_jump_in;
            if (opj_in <= `IJ_LAST_CONDITIONAL) num_jump_conditional <= num_jump_conditional + 1;
            else num_jump_call_indirect <= num_jump_call_indirect + 1;
        end
    end
    if (fast_jump_in) begin                                // fast jump/call/return bypassing pipeline
        num_jump_call_direct <= num_jump_call_direct + 1;
        if (!(instruction_valid_in && category_in == `CAT_JUMP)) begin
            num_jump_call_return <= num_jump_call_return + 1; // count also total jumps, except if counted above
        end
    end
    
    // reset counters
    if (reset_cpu_clock_cycles | reset) begin
        cpu_clock_cycles <= 0;
    end
    if (reset_num_instructions | reset) begin
        num_instructions <= 0;
        num_instructions_2size <= 0;
        num_instructions_3size <= 0;
        num_instructions_gp <= 0;   
        num_instructions_gp_mask0 <= 0;
    end
    if (reset_num_instructions_vector | reset) begin
        num_instructions_vector <= 0;
    end    
    if (reset_num_instructions_jump | reset) begin
        num_jump_call_return <= 0;       // count control transfer instructions
        num_jump_call_direct <= 0;       // count direct unconditional jumps and calls
        num_jump_call_indirect <= 0;     // count indirect jumps and calls
        num_jump_conditional <= 0;       // count conditional jumps        
    end
end

// Error detection. This is not controlled by clock enable because clock enable may stop when error is detected
always_ff @(posedge clock) begin
    error_last <= |errors_detect_in;     // error detected in last clock cycle
    clock_enabled_last <= clock_enable;  // clock was enabled in last clock cycle. new instruction encountered

    // A new error is detected if there was no error signal in the last clock cycle
    // of if clock_enable has allowed the execution of a new instruction
    if (|errors_detect_in && (clock_enabled_last || !error_last)) begin
        // a new error is detected. count it only once
        if      (errors_detect_in[0]) num_unknown_instruction <= num_unknown_instruction + 1;
        else if (errors_detect_in[1]) num_wrong_operands <= num_wrong_operands + 1;
        else if (errors_detect_in[2]) num_array_overflow <= num_array_overflow + 1;
        else if (errors_detect_in[3]) num_read_violation <= num_read_violation + 1;
        else if (errors_detect_in[4]) num_write_violation <= num_write_violation + 1;
        else if (errors_detect_in[5]) num_misaligned_memory <= num_misaligned_memory + 1;
    end
    
    // remember first error
    if (|errors_detect_in) begin
        if (!first_error_saved) begin
            if  (errors_detect_in[0]) begin
                first_error <= 1;
                first_error_address <= alu_instruction_pointer;
            end else if (errors_detect_in[1]) begin
                first_error <= 2;
                if (call_stack_overflow) first_error_address <= fetch_instruction_pointer;
                else first_error_address <= alu_instruction_pointer;
            end else if (errors_detect_in[2]) begin
                first_error <= 3;
                first_error_address <= dataread_instruction_pointer;
            end else if (errors_detect_in[3]) begin
                first_error <= 4;
                first_error_address <= dataread_instruction_pointer;
            end else if (errors_detect_in[4]) begin
                first_error <= 5;
                first_error_address <= dataread_instruction_pointer;
            end else if (errors_detect_in[5]) begin
                first_error <= 6;
                first_error_address <= dataread_instruction_pointer;
            end
        end
        first_error_saved <= 1;
    end

    if (reset_num_errors | reset) begin
        // reset error counters    
        num_unknown_instruction <= 0;    // count unknown instruction
        num_wrong_operands <= 0;         // count wrong operands for instructions
        num_array_overflow <= 0;         // count array index out of range
        num_read_violation <= 0;         // count memory read access violation
        num_write_violation <= 0;        // count memory write access violation
        num_misaligned_memory <= 0;      // count misaligned memory access
        first_error <= 0;
        first_error_address <= 0;
        first_error_saved <= 0;
    end
    if (clear_error_in) begin
        first_error_saved <= 0;          // debugger clear error
    end
    
    // reconstruct alu_instruction_pointer:        
    if (clock_enable & dataread_valid) begin
        alu_instruction_pointer <= dataread_instruction_pointer;
    end

end


// implement uart receiver
UART_RX UART_RX_inst (
    .reset(reset | fifo_buffer_input_reset | fifo_buffer_input_reset_error), // reset
    .clock(clock),                                         // clock at `CLOCK_RATE
    .rx_in(uart_bit_in),                                   // RX input
    .receive_complete_out(UART_RX_receive_complete),       // byte received. Will be high for 1 clock cycle after the middle of the stop bit
    .error_out(UART_RX_error),                             // transmission error. Remains high until reset in case of error
    .byte_out(UART_RX_byte_out)                            // byte output
);

// implement uart transmitter
UART_TX UART_TX_inst (
    .reset(reset | fifo_buffer_output_reset | fifo_buffer_output_reset_error), // reset 
   .clock(clock),                                          // clock at `CLOCK_RATE
   .start_in(fifo_buffer_output_ready),                    // command to send one byte
   .byte_in(fifo_buffer_output_byte),                      // byte input
   .active_out(UART_TX_active),                            // is busy
   .tx_out(uart_bit_out),                                  // TX output
   .done_out(UART_TX_done)                                 // will be high for one clock cycle shortly before the end of the stop bit
);

// implement fifo buffer for receiver
fifo_buffer #(.size_log2(`IN_BUFFER_SIZE_LOG2))  
fifo_buffer_input (
    .reset(reset | fifo_buffer_input_reset),               // reset everything
    .reset_error(reset | fifo_buffer_input_reset_error),   // clear error flags
    .clock(clock),                                         // clock at `CLOCK_RATE
    .read_next(fifo_buffer_input_read_next & clock_enable),// read next byte from buffer
    .write(UART_RX_receive_complete),                      // write one byte to buffer
    .byte_in(UART_RX_byte_out),                            // serial byte input
    .byte_out(fifo_buffer_input_byte),                     // serial byte output prefetched
    .data_ready_out(fifo_buffer_input_ready),              // the buffer contains at least one byte
    .overflow(fifo_buffer_input_overflow),                 // attempt to write to full buffer
    .underflow(fifo_buffer_output_underflow),              // attempt to read from empty buffer
    .num(fifo_buffer_input_num)                            // number of bytes currently in buffer
);

// implement fifo buffer for transmitter
fifo_buffer #(.size_log2(`OUT_BUFFER_SIZE_LOG2))  
fifo_buffer_output (
    .reset(reset | fifo_buffer_output_reset),              // reset everything
    .reset_error(reset | fifo_buffer_output_reset_error),  // clear error flags
    .clock(clock),                                         // clock at `CLOCK_RATE
    .read_next(UART_TX_done),                              // read next byte from buffer
    .write(fifo_buffer_output_write & clock_enable),       // write one byte to buffer
    .byte_in(serial_output_byte_in),                       // serial byte input
    .byte_out(fifo_buffer_output_byte),                    // serial byte output prefetched
    .data_ready_out(fifo_buffer_output_ready),             // the buffer contains at least one byte
    .overflow(fifo_buffer_output_overflow),                // attempt to write to full buffer
    .underflow(fifo_buffer_output_underflow),              // attempt to read from empty buffer
    .num(fifo_buffer_output_num)                           // number of bytes currently in buffer
);


endmodule