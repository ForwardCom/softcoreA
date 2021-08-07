//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2020-06-06
// Last modified:  2021-07-18
// Module Name:    data read
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description: Waiting stage after the address generator.
// This pipeline stage comes after the address generator. 
// It waits for a clock cycle while data retrieved from the data cache.
// Checks if a memory address is valid.
// Converts single format instructions to multiformat instruction code where possible
// Dispatches the instruction to the right execution unit.
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"


module dataread (
    input clock,                            // system clock (100 MHz)
    input clock_enable,                     // clock enable. Used when single-stepping
    input reset,                            // system reset
    input valid_in,                         // data from fetch module ready
    input stall_in,                         // a later stage in pipeline is stalled
    input [`CODE_ADDR_WIDTH-1:0] instruction_pointer_in, // address of current instruction
    input [63:0] instruction_in,            // current instruction, up to 3 words long
    input [`TAG_WIDTH-1:0] tag_val_in,      // instruction tag value    
    input        vector_in,                 // this is a vector instruction
    input [1:0]  category_in,               // 00: multiformat, 01: single format, 10: jump
    input [1:0]  format_in,                 // 00: format A, 01: format E, 10: format B, 11: format C (format D never goes through decoder)
    //input        rs_status_in,              // 1: RS is register operand
    //input        rt_status_in,              // 1: RT is register operand
    //input        ru_status_in,              // 1: RU is used
    //input        rd_status_in,              // 1: RD is used as input
    input        mask_status_in,            // 1: mask register used
    input        mask_alternative_in,       // mask register and fallback register used for alternative purposes
    input [1:0]  num_operands_in,           // number of source operands
    input [1:0]  result_type_in,            // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    input [1:0]  immediate_field_in,        // immediate data field. 0: none, 1: 8 bit, 2: 16 bit, 3: 32 or 64 bit
    input        memory_operand_in,         // The instruction has a memory operand
    input        array_error_in,            // Array index exceeds limit
    input        options3_in,               // IM3 containts option bits
     
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
    input [`RB:0]  operand1_in,             // value of first operand
    input [`RB:0]  operand2_in,             // value of second operand
    input [`RB:0]  operand3_in,             // value of last operand
    input [`MASKSZ:0] regmask_val_in,          // value of mask register
    input [`RB1:0] address_in,              // address of memory operand
    input [`RB1:0] ram_data_in,             // memory operand from data cache

    output reg        valid_out,            // An instruction is ready for output to next stage
    output reg [`CODE_ADDR_WIDTH-1:0] instruction_pointer_out, // address of current instruction
    output reg [31:0] instruction_out,      // first word of instruction    
    output reg        stall_predict_out,    // predict next stage will stall
    output reg [`TAG_WIDTH-1:0] tag_val_out,// instruction tag value
    output reg [`RB:0] operand1_out,        // value of first operand for 3-op instructions, bit `RB is 0 if valid 
    output reg [`RB:0] operand2_out,        // value of second operand, bit `RB is 0 if valid 
    output reg [`RB:0] operand3_out,        // value of last operand, bit `RB is 0 if valid 
    output reg [`MASKSZ:0] mask_val_out,    // value of mask, bit 32 is 0 if valid
    output reg         opr2_from_ram_out,   // value of operand 2 comes from data cache
    output reg         opr3_from_ram_out,   // value of last operand comes from data cache
    output reg         vector_out,          // this is a vector instruction
    output reg [1:0]   category_out,        // 00: multiformat, 01: single format, 10: jump
    output reg [1:0]   format_out,          // 00: format A, 01: format E, 10: format B, 11: format C (format D never goes through decoder)
    output reg [1:0]   num_operands_out,    // number of source operands
    output reg [1:0]   result_type_out,     // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    output reg         opr1_used_out,       // opr1_val_out is needed
    output reg         opr2_used_out,       // opr2_val_out is needed
    output reg         opr3_used_out,       // opr3_val_out is needed
    output reg         regmask_used_out,    // regmask_val_out is needed
    output reg         mask_alternative_out,// mask register and fallback register used for alternative purposes
    output reg [3:0]   exe_unit_out,        // each bit enables a particular execution unit:
                                            // 1: ALU, 10: MUL, 100: DIV, 1000: IN/OUT
    output reg [6:0]   opx_out,             // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
    output reg [5:0]   opj_out,             // operation ID for conditional jump instructions
    output reg [2:0]   ot_out,              // operand type
    output reg [5:0]   option_bits_out,     // option bits from IM3 or mask
    output reg [15:0]  im2_bits_out,        // constant bits from IM2 as extra operand    
    output reg         trap_out,            // trap instruction detected
    output reg         array_error_out,     // array index out of bounds
    output reg         read_address_error_out,       // invalid read memory address
    output reg         write_address_error_out,      // invalid write memory address
    output reg         misaligned_address_error_out, // misaligned read/write memory address
    output reg [31:0]  debug_out            // output for debugging 
);

// instruction components
logic [1:0]  il;                            // instruction length
logic [2:0]  mode;                          // instruction mode
logic [2:0]  mode2;                         // mode2 in format E
logic        M;                             // M bit
logic [2:0]  otype;                         // operand type in instruction
logic [5:0]  op1;                           // OP1 in instruction
logic [1:0]  op2;                           // OP2 in instruction
logic        is_addr_instr;                 // this is an address instruction
logic [5:0]  option_bits;                   // option bits
logic [15:0] im2_bits;                      // constant bits from IM2 as extra operand    
logic [1:0]  last_operand;                  // 0: last operand is a register, 
                                            // 1: last operand i an immediate constant
                                            // 2: last operand is memory
                                            // 3: both memory and immediate operands
logic        half_precision;                // half precision float
logic        swap_operands;                 // swap last two operands
logic [3:0]  exe_unit; 

// operand values. Extra bit is 1 if not found
logic [`RB:0] opr1_val;                     // first operand if 3 operands
logic [`RB:0] opr2_val;                     // first operand if 2 operands, second operand if 3 operands
logic [`RB:0] opr3_val;                     // last operand
logic [`MASKSZ:0] regmask_val;              // value of mask register, bit 32 indicates missing
logic        opr2_from_ram;                 // value of operand 2 comes from data ram
logic        opr3_from_ram;                 // value of last operand comes from data ram
logic        opr1_used;                     // operand 1 is used
logic        opr2_used;                     // operand 2 is used
logic        opr3_used;                     // operand 3 is used
logic        mask_off;                      // mask is zero
logic        stall_predict;                 // predict that alu will stall in next clock cycle
logic        read_address_error;            // invalid read memory address
logic        write_address_error;           // invalid write memory address
logic        misaligned_address_error;      // misaligned read/write memory address
logic [31:0] jump_offset;                   // relative jump offset

// converted operation id
logic [6:0]  opx;                           // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
logic [5:0]  opj;                           // operation ID for conditional jump instructions

// temporary storage of register values if found during stall. High bit is zero if valid
reg [`RB:0] opr1_val_temp;                  // value of first  operand, bit `RB indicates missing 
reg [`RB:0] opr2_val_temp;                  // value of second  operand, bit `RB indicates missing 
reg [`RB:0] opr3_val_temp;                  // value of last operand, bit `RB indicates missing 
reg [`MASKSZ:0] regmask_val_temp;           // value of mask register, bit 32 indicates missing
reg         last_stall;                     // was stalled in last clock cycle. May obtain register values from the temporary registers
reg         last_valid;                     // input was valid in last clock cycle. May obtain memory input

always_comb begin
    il   = instruction_in[`IL];             // instruction length
    mode = instruction_in[`MODE];           // format mode
    mode2 = instruction_in[`MODE2];         // format mode2
    M    = instruction_in[`M];              // M bit
    op1  = instruction_in[`OP1];            // op1 operation
    op2  = instruction_in[`OP2];            // op2 operation
    option_bits = 0;                        // option bits from IM3 etc.
    opr1_used = 0;                          // operand 1 used
    opr2_used = 0;                          // operand 2 used
    opr3_used = 0;                          // operand 3 used
    half_precision = 0;                     // float16. not implemented yet
    swap_operands = 0;                      // swap operands 2 and 3
    mask_off = 0;                           // mask known to be zero
    stall_predict = 0;                      // predict stall in next clock
    read_address_error = 0;                 // read address out of range
    write_address_error = 0;                // write address out of range
    misaligned_address_error = 0;           // read or write to misaligned address  
    opr2_from_ram = 0;                      // value of operand 2 comes from data memory
    opr3_from_ram = 0;                      // value of last operand comes from data memory
    im2_bits = instruction_in[`IM2E];       // IM2 may be used as extra immediate operand
    // look for address instruction in format 2.9A:
    is_addr_instr = (il == 2 && mode == 1 && M && op1 == `II_ADDRESS_29);
    
    // Detect operand type
    if (format_in == `FORMAT_C) begin
        otype = 2;                          // default operand type in format C is int32. 
        // Exceptions to format C operand type:
        if (mode == 1) begin                // format 1.1C. 
            if (op1[0]) otype = 3;          // optype is int64 when op1 is odd
        end
        if (mode == 4) begin                // format 1.4C. 
            if (op1 < 8) begin
                otype = 1;                  // optype is int16 when op1 < 8
            end else if (op1 < 32) begin
                otype = 2 | op1[0];         // optype is int32 for even op1, int64 for odd op1
            end else if (op1 < `II_ADD_H14) begin
                otype = 5 + op1[0];         // optype is float32 for even op1, float64 for odd op1
            end else begin 
                otype = 1;                  // 16 bits or float16
                half_precision = 1;         // half precision single format instructions
            end
        end
        if (mode == 7) begin                // format 1.7C
             if ((op1 & -2) == `IJ_SUB_MAXLEN_JPOS) otype = 3; // sub_maxlen/jump instruction has int64
        end
    end else if (vector_in) begin
        otype = instruction_in[`OT]; 
    end else begin
        otype = instruction_in[`OT] & 3'b011;
    end
    
    /*
    // detect if half precision
    if (category_in == `CAT_MULTI && op1 >= `II_ADD_FLOAT16 && op1 <= `II_MUL_ADD_FLOAT16) 
        half_precision = 1;  // half precision multiformat instructions
    if (category_in == `CAT_SINGLE && il == 1 && mode == 4 && op1 >= `II_ADD_H14 && op1 <= `II_MUL_H14)
        half_precision = 1;  // half precision single format instructions
    */
    // detect if last two operands should be swapped
    if (category_in == `CAT_MULTI && (op1 == `II_SUB_REV || op1 == `II_DIV_REV || op1 == `II_MUL_ADD2))   
        swap_operands = 1;

    // look for register values in result buses
    if      (last_stall && opr1_val_temp[`RB] == 0) opr1_val = opr1_val_temp;                                                      // obtained during stall
    else if (operand1_in[`RB] == 1 && write_en1 && operand1_in[`TAG_WIDTH-1:0] == write_tag1_in) opr1_val = {1'b0, writeport1_in}; // obtained from result bus 1
    else if (operand1_in[`RB] == 1 && write_en2 && operand1_in[`TAG_WIDTH-1:0] == write_tag2_in) opr1_val = {1'b0, writeport2_in}; // obtained from result bus 2
    else opr1_val = operand1_in;
        
    if      (last_stall && opr2_val_temp[`RB] == 0) opr2_val = opr2_val_temp;                                                      // obtained during stall
    else if (operand2_in[`RB] == 1 && write_en1 && operand2_in[`TAG_WIDTH-1:0] == write_tag1_in) opr2_val = {1'b0, writeport1_in}; // obtained from result bus 1
    else if (operand2_in[`RB] == 1 && write_en2 && operand2_in[`TAG_WIDTH-1:0] == write_tag2_in) opr2_val = {1'b0, writeport2_in}; // obtained from result bus 2
    else opr2_val = operand2_in;
        
    if      (operand3_in[`RB] == 1 && write_en1 && operand3_in[`TAG_WIDTH-1:0] == write_tag1_in) opr3_val = {1'b0, writeport1_in}; // obtained from result bus 1
    else if (operand3_in[`RB] == 1 && write_en2 && operand3_in[`TAG_WIDTH-1:0] == write_tag2_in) opr3_val = {1'b0, writeport2_in}; // obtained from result bus 2
    else if (last_stall && opr3_val_temp[`RB] == 0) opr3_val = opr3_val_temp;                                                      // obtained during stall
    else opr3_val = operand3_in;  
      
    if      (last_stall && regmask_val_temp[`MASKSZ] == 0) regmask_val = regmask_val_temp;                                                      // obtained during stall
    if      (regmask_val_in[`MASKSZ] == 1 && write_en1 && regmask_val_in[`TAG_WIDTH-1:0] == write_tag1_in) regmask_val = {1'b0, writeport1_in[`MASKSZ-1:0]}; // obtained from result bus 1
    else if (regmask_val_in[`MASKSZ] == 1 && write_en2 && regmask_val_in[`TAG_WIDTH-1:0] == write_tag2_in) regmask_val = {1'b0, writeport2_in[`MASKSZ-1:0]}; // obtained from result bus 2
    else regmask_val = regmask_val_in;
    
    // look for memory operand
    if (memory_operand_in) begin
        if (last_stall && last_valid) begin
            // value from data memory is available early because of stall
            if (immediate_field_in != `IMMED_NONE) begin
                opr2_val = ram_data_in;
            end else begin
                opr3_val = ram_data_in;
            end    
        end else begin
            if (immediate_field_in != `IMMED_NONE) begin
                opr2_from_ram = 1;
            end else begin
                opr3_from_ram = 1;
            end    
        end
    end
    
    // check if memory operand is valid
    // (this check is not placed in the address generator stage because of timing constraints)
    if (valid_in && memory_operand_in && !is_addr_instr) begin
    
        // invalid read memory address:
        read_address_error = result_type_in != `RESULT_MEM &&
            address_in >= 2**`DATA_ADDR_WIDTH; // can read from data only
                  
        // Invalid write memory address:
        // To do: fix this when write access to code memory is removed.
        // Note: The calculation of write_address_error is not done in the address generator
        // stage because of critical timing. It is too late to disable illegal writes in this 
        // stage. We must find a solution to this in future versions with memory protection.
        // For now, we will be satisfied with program halt.
        write_address_error = result_type_in == `RESULT_MEM &&
            address_in >= 2**`COMMON_ADDR_WIDTH; // can write to data or code
        
        // misaligned read/write memory address:
        case (otype)
        0:  // int8
            misaligned_address_error = 0;
        1:  // int16
            misaligned_address_error = address_in[0];
        2, 5:  // int32, float32
            misaligned_address_error = address_in[1:0] != 0;        
        3, 6:  // int64, float64
            misaligned_address_error = address_in[2:0] != 0;
        4, 7:  // int128, float128
            misaligned_address_error = address_in[3:0] != 0;
        endcase
    end
    
    // find jump offset
    jump_offset = 0;
    
    if (category_in == `CAT_JUMP) begin
        if (il == 1 && mode == 6) begin
            // 1.6 B: Short jump with two register operands and 8 bit offset (IM1).
            jump_offset = {{24{instruction_in[`IM1S]}},instruction_in[`IM1]}; // sign extend            
        
        end else if (il == 1 && mode == 7) begin
            // 1.7 C: Short jump with one register operand, an 8-bit immediate constant (IM2) and 8 bit offset (IM1),
            jump_offset = {{24{instruction_in[`IM1S]}},instruction_in[`IM1]}; // sign extend
        
        end else if (il == 2 && mode == 5) begin
            if (op1 == 0) begin
                // 2.5.0A: Double size jump with three register operands and 24 bit jump offset
                jump_offset = {{8{instruction_in[55]}},instruction_in[55:32]}; // sign extend 24 bit offset
            
            end else if (op1 == 1) begin
                // format 2.5.1B: jump with one register, one 16 bit operand, and 16 bit offset            
                jump_offset = {{16{instruction_in[63]}},instruction_in[63:48]}; // sign extend 16 bit offset
        
            end else if (op1 == 2) begin
                // format 2.5.2B: jump with one register, a memory operand with 16 bit address, and 16 bit offset            
                jump_offset = {{16{instruction_in[63]}},instruction_in[63:48]}; // sign extend 16 bit offset
        
            end else if (op1 == 4) begin
                // format 2.5.4C: jump with one register, one 8 bit operand, and 32 bit offset
                jump_offset = instruction_in[63:32]; // 32 bit offset
        
            end else if (op1 == 5) begin
                // format 2.5.5C: jump with one register, one 32 bit operand, and 8 bit offset
                jump_offset = {{24{instruction_in[15]}},instruction_in[15:8]}; // sign extend 8 bit offset
            
            end
        
        end else if (il == 3 && mode == 1) begin
            if (op1 == 0) begin
                // 3.1.0A: Triple size jump with two register operands and 24 bit jump offset and 32 bit address
                jump_offset = {{8{instruction_in[55]}},instruction_in[55:32]}; // sign extend 24 bit offset
            end else if (op1 == 1) begin
                // 3.1.1B: Jump with two registers, a 32 bit operand, and 32 bit jump offset
                jump_offset = instruction_in[63:32]; // 32 bit jump offset
            end
        end    
    end 
    
    // get condition code for jump instructions
    opj = 0;
    if (category_in == `CAT_JUMP) begin
        if (il == 1) begin
            if (mode == 7 && op1 <= `II_UNCOND_JUMP) opj = 0;   // unconditional jump or call handled by fetch unit
            else if (op1 == `II_RETURN) opj = 0;                // return handled by fetch unit 
            else opj = op1;
        end else if (il == 2 && mode == 5 && op1 == 0) begin  
            opj = instruction_in[61:56];                        // format 2.5.0A: opj in upper part of IM2
        end else if (il == 2 && mode == 5 && op1 == 7) begin    // system call
            opj = `IJ_SYSCALL;
        end else if (il == 3 && mode == 1 && op1 == 0) begin  
            opj = instruction_in[61:56];                        // format 3.1.0A: opj in upper part of IM2
        end else if (op1 < 8) begin                             // other jump formats have opj in IM1
            opj = instruction_in[5:0];
        end else begin
            opj = 56;                                           // unknown 
        end
    end
    
    // get option bits
    if (options3_in && format_in == `FORMAT_E) begin
        option_bits = instruction_in[`IM3E];                    // option bits in IM3    
    end else if (category_in == `CAT_JUMP) begin
        // imitate compare instruction option bits for compare/jump
        case (opj[5:1])
        // ignore bit 0 of opj here: it is inserted in the alu stage
        `IJ_COMPARE_JEQ>>1: option_bits = 4'b0000;
        `IJ_COMPARE_JSB>>1: option_bits = 4'b0010;
        `IJ_COMPARE_JSA>>1: option_bits = 4'b0100;
        `IJ_COMPARE_JUB>>1: option_bits = 4'b1010;
        `IJ_COMPARE_JUA>>1: option_bits = 4'b1100;
        endcase
    end else if (category_in == `CAT_MULTI && op1 >= `II_MIN && op1 <= `II_MAX_U) begin
        // use compare unit to implement max and min
        case (op1[1:0])
        0: option_bits = 4'b0010;      // min, signed 
        1: option_bits = 4'b1010;      // min, unsigned 
        2: option_bits = 4'b0100;      // max, signed 
        3: option_bits = 4'b1100;      // max, unsigned
        endcase
    end
    
    // convert op1 to opx: operation id in execution unit
    opx = `IX_UNDEF;                             // default is undefined
    if (category_in == `CAT_MULTI) begin
        opx = op1;                               // mostly same id for multiformat instructions
        if (op1 == `II_SUB_REV) opx = `II_SUB;   // operands have been swapped 
        if (op1 == `II_DIV_REV) opx = `II_DIV;   // operands have been swapped
         
    end else if (category_in == `CAT_JUMP) begin
        // convert jump instructions to corresponding general ALU instructions
        if      (opj <= `IJ_SUB_JBORROW + 1)    opx = `II_SUB;
        else if (opj <= `IJ_AND_JZ + 1)         opx = `II_AND;
        else if (opj <= `IJ_OR_JZ + 1)          opx = `II_OR;
        else if (opj <= `IJ_XOR_JZ + 1)         opx = `II_XOR;
        else if (opj <= `IJ_ADD_JCARRY + 1)     opx = `II_ADD;
        else if (opj <= `IJ_AND_JZ + 1)         opx = `II_AND;
        else if (opj <= `IJ_TEST_BIT_JTRUE + 1) opx = `II_TEST_BIT;
        else if (opj <= `IJ_TEST_BITS_AND + 1)  opx = `II_TEST_BITS_AND;
        else if (opj <= `IJ_TEST_BITS_OR + 1)   opx = `II_TEST_BITS_OR;
        else if (opj <= `IJ_COMPARE_JUA + 1)    opx = `II_COMPARE;
        else if ((opj & ~1) == `II_INDIRECT_JUMP) begin // 58
            if ((il == 1 && mode == 6) || (il == 2 && mode == 5 && op1[2:0] == 2))
                 opx = `IX_INDIRECT_JUMP;  // indirect jump w memory operand, format 1.6 and 2.5.2
            else opx = `IX_UNCOND_JUMP;    // unconditional jump format 2.5.4 and 3.1.1            
        end else if ((opj & ~1) == `II_JUMP_RELATIVE) begin // 60
            if (il == 1 && mode == 7) opx = `IX_INDIRECT_JUMP;
            else opx = `IX_RELATIVE_JUMP;
        end 
        else opx = 0;
        
    end else if (il == 1 && mode == 1) begin
        // format 1.1 C. single format instructions with 16 bit constant
        case (op1[5:1])  // even and odd op1 values treated together, they differ only by operand type
        `II_ADD11 >> 1:         opx = `II_ADD;
        `II_MUL11 >> 1:         opx = `II_MUL;
        `II_ADDSHIFT16_11 >> 1: opx = `II_ADD;
        `II_SHIFT_ADD_11 >> 1:  opx = `II_ADD;
        `II_SHIFT_AND_11 >> 1:  opx = `II_AND;
        `II_SHIFT_OR_11 >> 1:   opx = `II_OR;
        `II_SHIFT_XOR_11 >> 1:  opx = `II_XOR;
        default:                opx = `IX_UNDEF;
        endcase
        if (op1 <= `II_MOVE11_LAST) opx = `II_MOVE; // five different move instructions
        
    end else if (il == 1 && mode == 0 && M) begin
        // format 1.8 B. single format instructions with 8 bit constant
        case (op1)
        `II_SHIFT_ABS18:   opx = `IX_ABS;
        `II_BITSCAN_18:    opx = `IX_BIT_SCAN;
        `II_ROUNDP2_18:    opx = `IX_ROUNDP2;
        `II_POPCOUNT_18:   opx = `IX_POPCOUNT;        
        `II_READ_SPEC18:   opx = `IX_READ_SPEC;
        `II_WRITE_SPEC18:  opx = `IX_WRITE_SPEC;
        `II_READ_CAP18:    opx = `IX_READ_CAPABILITIES;
        `II_WRITE_CAP18:   opx = `IX_WRITE_CAPABILITIES;
        `II_READ_PERF18:   opx = `IX_READ_PERF;
        `II_READ_PERFS18:  opx = `IX_READ_PERFS;
        `II_READ_SYS18:    opx = `IX_READ_SYS;
        `II_WRITE_SYS18:   opx = `IX_WRITE_SYS;
        `II_INPUT_18:      opx = `IX_INPUT;
        `II_OUTPUT_18:     opx = `IX_OUTPUT;        
        endcase
        
    end else if (il == 2 && (mode == 0 && !M || mode == 2) && mode2 == 6) begin // format 2.0.6 and 2.2.6
        if (op1 == `II_TRUTH_TAB3 && op2 == `II2_TRUTH_TAB3) opx = `IX_TRUTH_TAB3;        
        
    end else if (il == 2 && (mode == 0 && !M || mode == 2) && mode2 == 7) begin
        // format 2.0.7 and 2.2.7 single format
        if (op1 == `II_MOVE_BITS && op2 == `II2_MOVE_BITS) begin // move_bits instruction. 
            // Do calculations on constant operands here to save critical time in the alu stage
            logic [5:0] move_from;                 // bit position to move from
            logic [5:0] move_to;                   // bit position to move to
            logic [5:0] num_bits;                  // number of bits to move
            logic [6:0] end_to;                    // end of destination bit field
            move_from = instruction_in[37:32];     // low part of im2
            move_to   = instruction_in[45:40];     // high part of im2            
            num_bits  = instruction_in[`IM3E];     // number of bits to move
            if (move_from > move_to) begin         // IX_MOVE_BITS2 if shifting right
                opx = `IX_MOVE_BITS2;
            end else begin
                opx = `IX_MOVE_BITS1;              // IX_MOVE_BITS1 if shifting left
            end
            end_to = {1'b0,move_to} + num_bits - 1;// end of destination bit field. 
            if (end_to[6]) option_bits[5:0] = 6'b111111; // saturate on overflow
            else option_bits = end_to[5:0];
            // begin of destination bit field is in im2_bits[13:8]
            // end of destination bit field is in option_bits
            opr3_val[7:0] = move_from - move_to;   // shift right count, or -(shift left count)
        end
        
    end else if (il == 2 && mode == 5) begin
        // format 2.5 B. single format instructions with 32 bit constant
        if (op1 == `II_STOREI) opx = `II_STORE;
        
    end else if (il == 2 && mode == 1 && M) begin
        // format 2.9A. single format instructions with 32 bit constant
        case (op1)
        `II_MOVE_HI_29:    opx = `II_MOVE;  // shifted left by 32 here. just store result
        `II_INSERT_HI_29:  opx = `IX_INSERT_HI;
        `II_ADDU_29:       opx = `II_ADD;
        `II_SUBU_29:       opx = `II_SUB;
        `II_ADD_HI_29:     opx = `II_ADD;
        `II_AND_HI_29:     opx = `II_SUB;
        `II_OR_HI_29:      opx = `II_OR;
        `II_XOR_HI_29:     opx = `II_XOR;
        `II_ADDRESS_29:    opx = `II_MOVE; // address instruction. resolved in this state. just store result  
        endcase     
    end
    
    // select execution unit
    if (opx == `IX_INPUT || opx == `IX_OUTPUT || (opx >= `IX_READ_CAPABILITIES && opx <= `IX_WRITE_SYS+1)) begin 
        exe_unit = 4'b1000;      // input/output unit. also handles system registers
    end else if (opx >= `II_DIV && opx <= `II_REM_U) begin 
        exe_unit = 4'b0100;      // division unit
    end else if ((opx >= `II_MUL && opx <= `II_MUL_HI_U) || opx == `II_MUL_ADD || opx == `II_MUL_ADD2) begin    
        exe_unit = 4'b0010;      // multiplication unit
    end else begin
        exe_unit = 4'b0001;      // general ALU unit
    end
    
    // find which operands are used
    mask_off = result_type_in != `RESULT_MEM && mask_status_in && regmask_val[`MASKSZ] == 0 && regmask_val[0] == 0 && !mask_alternative_in && !vector_in; 

    if (mask_status_in) begin
        if (regmask_val[`MASKSZ] == 0) begin
            // a mask is used and the value is already available
            if (regmask_val[0]) begin
                // mask is 1. operands are needed. fallback not needed
                if (num_operands_in > 0) opr3_used = 1;
                if (num_operands_in > 1) opr2_used = 1;
                if (num_operands_in > 2) opr1_used = 1;
            end else begin
                // mask is 0. operands are not needed. fallback is needed
                opr1_used = 1;
            end
        end else begin
            // a mask is used. The value is not available yet. operands and fallback are needed
            if (num_operands_in > 0) opr3_used = 1;
            if (num_operands_in > 1) opr2_used = 1;
            opr1_used = 1;
        end
    end else begin
        // mask not used. fallback not needed
        if (num_operands_in > 0) opr3_used = 1;
        if (num_operands_in > 1) opr2_used = 1;
        if (num_operands_in > 2) opr1_used = 1;
    end
    
    if (mask_alternative_in) opr1_used = 1; // alternative use of fallback register
    
    // predict stall in ALU
    stall_predict = 
        (opr1_used && opr1_val[`RB] && predict_tag1_in != opr1_val[`TAG_WIDTH-1:0] && predict_tag2_in != opr1_val[`TAG_WIDTH-1:0]) ||
        (opr2_used && opr2_val[`RB] && predict_tag1_in != opr2_val[`TAG_WIDTH-1:0] && predict_tag2_in != opr2_val[`TAG_WIDTH-1:0] && !mask_off) ||
        (opr3_used && opr3_val[`RB] && predict_tag1_in != opr3_val[`TAG_WIDTH-1:0] && predict_tag2_in != opr3_val[`TAG_WIDTH-1:0] && !mask_off) ||
        (mask_status_in && regmask_val[`MASKSZ] && predict_tag1_in != regmask_val[`TAG_WIDTH-1:0] && predict_tag2_in != regmask_val[`TAG_WIDTH-1:0]); 
end

// save values from result bus during stall
always_ff @(posedge clock) if (clock_enable) begin
    if (stall_in) begin
        opr1_val_temp    <= opr1_val;      // temporary save during stall
        opr2_val_temp    <= opr2_val;      // temporary save during stall
        opr3_val_temp    <= opr3_val;      // temporary save during stall
        regmask_val_temp <= regmask_val;   // temporary save during stall
    end else begin
        opr1_val_temp    <= {1'b1,`RB'b0}; // reset when not stalled
        opr2_val_temp    <= {1'b1,`RB'b0}; // reset when not stalled
        opr3_val_temp    <= {1'b1,`RB'b0}; // reset when not stalled
        regmask_val_temp <= {1'b1,`MASKSZ'b0}; // reset when not stalled    
    end
end

// output operands
always_ff @(posedge clock) if (clock_enable && !stall_in) begin
    if (!swap_operands) begin // normal operand order
    
        // jump instructions
        if (category_in == `CAT_JUMP) begin 
            if (opj < `IJ_JUMP_INDIRECT_MEM || opx == `IX_UNCOND_JUMP) begin
                // calculate jump target = ip + il + offset (il cannot be 0 for jump instructions)
                operand1_out[`RB1:0] <= instruction_pointer_in + {{32{jump_offset[31]}},jump_offset} + il;
                operand1_out[`RB] <= 0;     // indicate not missing
            end else begin
                // target address not known yet. Make sure we don't accidentally assume no jump
                operand1_out <= ~(`RB'b0);  // -1 for unknown target address
            end
        end else begin 
            operand1_out <= opr1_val;
        end
        operand2_out <= opr2_val;
        operand3_out <= opr3_val;
        opr2_from_ram_out <= opr2_from_ram; // value of operand 2 comes from data cache
        opr3_from_ram_out <= opr3_from_ram; // value of last operand comes from data cache
        opr1_used_out <= opr1_used;
        opr2_used_out <= opr2_used;
        opr3_used_out <= opr3_used;
        // disable ram input if error (removed because of critical timing):
        /*
        if (array_error_in || read_address_error) begin
            opr2_from_ram_out <= 0;
            opr3_from_ram_out <= 0;
            if (opr2_from_ram) operand2_out <= 0;
            if (opr3_from_ram) operand3_out <= 0;
        end*/

    end else begin // swap last two operands
        operand1_out <= opr1_val;
        operand2_out <= opr3_val;
        operand3_out <= opr2_val;
        opr2_from_ram_out <= opr3_from_ram; // value of operand 2 comes from data cache
        opr3_from_ram_out <= opr2_from_ram; // value of last operand comes from data cache    
        opr1_used_out <= opr1_used;
        opr2_used_out <= opr3_used;
        opr3_used_out <= opr2_used;
        // disable ram input if error (removed because of critical timing):
        /*
        if (array_error_in || read_address_error) begin
            opr2_from_ram_out <= 0;
            opr3_from_ram_out <= 0;
            if (opr2_from_ram) operand3_out <= 0;
            if (opr3_from_ram) operand2_out <= 0;
        end*/
    end    

    mask_val_out <= regmask_val;
    
    // other outputs
    regmask_used_out <= mask_status_in;
    instruction_pointer_out <= instruction_pointer_in; // address of current instruction
    instruction_out <= instruction_in[31:0];
    tag_val_out <= tag_val_in;              // instruction tag value
    vector_out <= vector_in;                // this is a vector instruction
    mask_alternative_out <= mask_alternative_in;    
    opx_out <= opx;                         // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
    opj_out <= opj;                         // operation ID for conditional jump instructions
    ot_out <= otype;                        // operand type
    option_bits_out <= option_bits;         // option bits in format E
    im2_bits_out <= im2_bits;               // constant bits from IM2 as extra operand    

    result_type_out <= result_type_in;      // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    num_operands_out <= num_operands_in;    // number of source operands
    category_out <= category_in;            // 00: multiformat, 01: single format, 10: jump
    format_out <= format_in;                // 00: format A, 01: format E, 10: format B, 11: format C (format D never goes through decoder)
    
    // choose which execution unit to use
    exe_unit_out <= exe_unit;
    // detect trap instruction. will enable single step mode in next clock cycle
    trap_out <= (il == 1 && mode == 7 && op1 == `IJ_TRAP && valid_in);
end

always_ff @(posedge clock) if (clock_enable) begin

    if (reset) valid_out <= 0;
    else if (!stall_in) valid_out <= valid_in;    

    last_stall <= stall_in & valid_in;
    last_valid <= valid_in;    
    array_error_out <= array_error_in & valid_in;                        // array index out of bounds
    read_address_error_out <= read_address_error & valid_in;             // invalid read memory address
    write_address_error_out <= write_address_error & valid_in;           // invalid write memory address
    misaligned_address_error_out <= misaligned_address_error & valid_in; // misaligned read/write memory address
    
    // predict stall
    if (exe_unit[2] && 0) begin
        stall_predict_out <= valid_in; // To do: stall if div unit busy
    end else begin 
        stall_predict_out <= stall_predict && valid_in && !stall_in;     // not all operands and units are ready    
    end
    
    // debug output
    debug_out <= 0;
    debug_out[1:0] <= result_type_in;
    debug_out[5:4] <= num_operands_in;
    debug_out[9:8] <= mask_status_in;
    debug_out[10]  <= mask_alternative_in;
    debug_out[11]  <= mask_off;
    
    debug_out[12]  <= regmask_val[0];
    debug_out[15]  <= regmask_val[`MASKSZ];
    
    debug_out[16]  <= opr1_used;
    debug_out[17]  <= opr2_used;
    debug_out[18]  <= opr3_used;
    debug_out[19]  <= swap_operands;
    
    debug_out[20]  <= stall_predict;
    
    debug_out[25:24]  <= il;
    
        
end

endmodule
