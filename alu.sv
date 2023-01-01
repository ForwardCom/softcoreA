//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:   2020-06-06
// Last modified: 2022-12-25
// Module Name: decoder
// Project Name: ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions: Vivado v. 2020.1
// License: CERN-OHL-W
// Description: Arithmetic-logic unit for general purpose registers.
// Executes add, subtract, bit manipulation, etc.
//////////////////////////////////////////////////////////////////////////////////

`include "defines.vh"
`include "subfunctions.vh"

module alu (
    input clock,                            // system clock
    input clock_enable,                     // clock enable. Used when single-stepping
    input reset,                            // system reset
    input valid_in,                         // data from previous stage ready
    
    input [`CODE_ADDR_WIDTH-1:0] instruction_pointer_in, // address of current instruction
    input [31:0] instruction_in,            // current instruction, only first word used here
    input [`TAG_WIDTH-1:0] tag_val_in,      // instruction tag value    
    input [1:0]  category_in,               // 00: multiformat, 01: single format, 10: jump
    input        mask_alternative_in,       // mask register and fallback register used for alternative purposes
    input [1:0]  result_type_in,            // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    input        vector_in,                 // vector registers used
    input [6:0]  opx_in,                    // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
    input [5:0]  opj_in,                    // operation ID for conditional jump instructions
    input [2:0]  ot_in,                     // operand type
    input [5:0]  option_bits_in,            // option bits from IM5 or mask
    input [15:0] im4_bits_in,               // constant bits from IM4 as extra operand    
     
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
    input [`RB:0] operand1_in,              // first register operand or fallback
    input [`RB:0] operand2_in,              // second register operand RS
    input [`RB:0] operand3_in,              // last register operand RT
    input [`MASKSZ:0] mask_val_in,          // mask register
    input [`RB1:0] ram_data_in,             // memory operand from data ram
    input opr2_from_ram_in,                 // value of operand 2 comes from data ram
    input opr3_from_ram_in,                 // value of last operand comes from data ram    
    input opr1_used_in,                     // operand1_in is needed
    input opr2_used_in,                     // operand2_in is needed
    input opr3_used_in,                     // operand3_in is needed
    input mask_used_in,                     // mask_val_in is needed

    output reg valid_out,                   // for debug display: alu is active
    output reg register_write_out, 
    output reg [5:0] register_a_out,        // register to write
    output reg [`RB1:0] result_out,         // output result to destination register
    output reg [`TAG_WIDTH-1:0] tag_val_out,// instruction tag value
    output reg jump_out,                    //  jump instruction: jump taken
    output reg nojump_out,                  // jump instruction: jump not taken
    output reg [`CODE_ADDR_WIDTH-1:0] jump_pointer_out, // jump target to fetch unit
    output reg stall_out,                   // alu is waiting for an operand or not ready to receive a new instruction
    output reg stall_next_out,              // alu will be waiting in next clock cycle 
    output reg error_out,                   // unknown instruction
    output reg error_parm_out,              // wrong parameter for instruction

    // outputs for debugger:
    output reg [31:0] debug1_out,           // debug information
    output reg [31:0] debug2_out            // temporary debug information
);

logic [`RB1:0] operand1;                    // first register operand RD or RU. bit `RB is 1 if invalid 
logic [`RB1:0] operand2;                    // second register operand RS. bit `RB is 1 if invalid
logic [`RB1:0] operand3;                    // last register operand RT. bit `RB is 1 if invalid
logic [`MASKSZ:0] mask_val;                 // mask register
logic [1:0]  otout;                         // operand type for output
logic [5:0]  msb;                           // index to most significant bit
logic signbit2, signbit3;                   // sign bits of operands
logic [`RB1:0] sbit;                        // position of sign bit 
logic [`RB1:0] result;                      // result for output
logic [1:0]  result_type;                   // type of result
logic [6:0]  opx;                           // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
logic [6:0]  opj;                           // operation ID for conditional jump
logic jump_result;                          // result of jump condition (needs inversion if opj[0])

logic mask_off;                             // result is masked off
logic stall;                                // waiting for operands
logic stall_next;                           // will be waiting for operands in next clock cycle
logic error;                                // unknown instruction
logic error_parm;                           // wrong parameter for instruction
logic jump_taken;                           // conditional jump is jumping
logic jump_not_taken;                       // conditional jump is not jumping or target follows immediately
logic normal_output;                        // normal register output

logic [`CODE_ADDR_WIDTH-1:0] nojump_target; // next address if not jumping
logic [`CODE_ADDR_WIDTH-1:0] relative_jump_target; // jump target for multiway relative jump
// It seems to be more efficient to truncate operands locally by ANDing with sizemask than to 
// make separate wires for the truncated operands, because wiring is more expensive than logic:
logic [`RB1:0] sizemask;                    // mask for operand type

always_comb begin
    stall       = 0;
    stall_next  = 0;    
    mask_val = 0;
    
    // get all inputs
    if (mask_val_in[`MASKSZ]) begin      // value missing
        if (write_en1 && mask_val_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            mask_val = writeport1_in;    // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && mask_val_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            mask_val = writeport2_in[(`MASKSZ-1):0]; // obtained from result bus 2
        end else begin
            if (mask_used_in) begin
                stall = 1;                  // operand not ready
                if (mask_val_in[`TAG_WIDTH-1:0] != predict_tag1_in && mask_val_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                    stall_next = 1;         // operand not ready in next clock cycle
                end
            end                 
        end
    end else begin  // value available
        mask_val = mask_val_in;
    end

    // result is masked off
    mask_off = mask_used_in && mask_val[`MASKSZ] == 0 && mask_val[0] == 0 && !mask_alternative_in; 
    
    operand1 = 0;    
    if (operand1_in[`RB]) begin             // value missing
        if (write_en1 && operand1_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            operand1 = writeport1_in;       // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && operand1_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            operand1 = writeport2_in;       // obtained from result bus 2
        end else begin
            if (opr1_used_in) begin
                stall = 1;                  // operand not ready
                if (operand1_in[`TAG_WIDTH-1:0] != predict_tag1_in && operand1_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                    stall_next = 1;         // operand not ready in next clock cycle
                end                 
            end
        end
    end else begin
        operand1 = operand1_in[`RB1:0];
    end 

    operand2 = 0;
    if (opr2_from_ram_in) begin
        operand2 = ram_data_in;        
    end else if (operand2_in[`RB]) begin    // value missing
        if (write_en1 && operand2_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            operand2 = writeport1_in;       // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && operand2_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            operand2 =  writeport2_in;      // obtained from result bus 2
        end else begin
            if (opr2_used_in /*&& !mask_off*/) begin  // mask_off removed because of critical timing
                stall = 1;                  // operand not ready
                if (operand2_in[`TAG_WIDTH-1:0] != predict_tag1_in && operand2_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                    stall_next = 1;         // operand not ready in next clock cycle
                end                 
            end
        end 
    end else begin // value available
        operand2 = operand2_in[`RB1:0];
    end
        
    operand3 = 0;    
    if (opr3_from_ram_in) begin
        operand3 = ram_data_in;        
    end else if (operand3_in[`RB]) begin    // value missing
        if (write_en1 && operand3_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            operand3 = writeport1_in;       // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && operand3_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            operand3 = writeport2_in;       // obtained from result bus 2
        end else begin
            if (opr3_used_in /*&& !mask_off*/) begin // mask_off removed because of critical timing
                stall = 1;                  // operand not ready
                if (operand3_in[`TAG_WIDTH-1:0] != predict_tag1_in && operand3_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                    stall_next = 1;         // operand not ready in next clock cycle
                end                 
            end
        end
    end else begin // value available
        operand3 = operand3_in[`RB1:0];
    end
     
    opx = opx_in;       // operation ID in execution unit
    opj = opj_in;       // operation ID for conditional jump
    result = 0;
    jump_result = 0;
    otout = ot_in[1:0]; // operand type for output
    result_type = result_type_in;
    jump_taken = 0;
    jump_not_taken = 0;
    nojump_target = 0;
    relative_jump_target = 0;
    error = 0;
    error_parm = 0;

    // auxiliary variables depending on operand type
    case (ot_in[1:0])
    0: begin                     // 8 bit
        msb      = 7;            // most significant bit
        sbit     = 8'H80;        // sign bit
        sizemask = 8'HFF;        // mask off unused bits
        signbit2 = operand2[7];  // sign bit of operand 2
        signbit3 = operand3[7];  // sign bit of operand 3
        end
    1: begin                     // 16 bit
        msb      = 15;           // most significant bit
        sbit     = 16'H8000;     // sign bit
        sizemask = 16'HFFFF;     // mask off unused bits
        signbit2 = operand2[15]; // sign bit of operand 2
        signbit3 = operand3[15]; // sign bit of operand 3
        end           
    2: begin                     // 32 bit
        msb      = 31;           // most significant bit 
        sbit     = 32'H80000000; // sign bit
        sizemask = 32'HFFFFFFFF; // mask off unused bits
        signbit2 = operand2[31]; // sign bit of operand 2
        signbit3 = operand3[31]; // sign bit of operand 3     
        end
    3: begin                     // 64 bit, or 32 if 64 bit not supported
        msb      = `RB1;         // most significant bit
        sbit     = {1'b1,{(`RB-1){1'b0}}}; // sign bit
        sizemask = ~(`RB'b0);    // mask off unused bits      
        signbit2 = operand2[`RB1]; // sign bit of operand 2
        signbit3 = operand3[`RB1]; // sign bit of operand 3
        end
    endcase
    
    
    
    ////////////////////////////////////////////////
    //             Select ALU operation
    ////////////////////////////////////////////////
    
    if (opx == `II_MOVE || opx == `II_STORE) begin
        // simple move instructions
        result = operand3;

    end else if (opx == `IX_READ_SPEC || opx == `IX_WRITE_SPEC) begin
        // read or write special registers
        result = operand2;    
      
    end else if (opx == `II_SIGN_EXTEND || opx == `II_SIGN_EXTEND_ADD || opx == `IX_RELATIVE_JUMP) begin
        // instructions involving sign extension
        logic [`RB1:0] sign_ex;    // result of sign extension
        logic [`RB1:0] sign_ex_sc; // result of sign extension and scaling
        otout = 3;                 // 64 bit output
        // sign extend:
        case (ot_in[1:0])
        0: sign_ex = {{56{operand3[ 7]}},operand3[7:0]};    // 8 bit
        1: sign_ex = {{48{operand3[15]}},operand3[15:0]};   // 16 bit
        2: sign_ex = {{32{operand3[31]}},operand3[31:0]};   // 32 bit
        3: sign_ex = operand3[`RB1:0];                      // 64 bit
        endcase
        if (opx == `II_SIGN_EXTEND_ADD) begin
            // scale sign_ex.
            // The scale factor is limited to 3 here for timing reasons so that it fits a 6-input LUT
            // A full barrel shifter takes too much time
            case (option_bits_in[1:0])       // optional shift count in option bits
            0: sign_ex_sc =  sign_ex;        // scale factor 1
            1: sign_ex_sc = {sign_ex,1'b0};  // scale factor 2
            2: sign_ex_sc = {sign_ex,2'b0};  // scale factor 4
            3: sign_ex_sc = {sign_ex,3'b0};  // scale factor 8
            endcase
            result = sign_ex_sc + operand2;  // add
            if (|(option_bits_in[5:2])) error_parm = 1; // shift count > 3
          
        end else begin
            result = sign_ex;
        end
        if (opx == `IX_RELATIVE_JUMP) begin
            relative_jump_target = sign_ex + operand2[`RB1:2] - {1'b1,{(`CODE_ADDR_START-2){1'b0}}}; // subtract (code memory start)/4
            if (|(operand2[1:0])) error_parm = 1; // jump to misaligned address
        end
        
    end else if (opx == `IX_INDIRECT_JUMP) begin
        // jump address calculated below
        if (|(operand3[1:0])) error_parm = 1;    // misaligned jump target        
        
    end else if (opx == `II_COMPARE || opx == `II_MIN || opx == `II_MAX) begin
        // instructions involving signed and unsigned compare. operation defined by option bits
        logic b1, b2, b3, eq, less;  // intermediate results
        logic [`RB1:0] sbit1;
        b1 = 0; b2 = 0; b3 = 0; eq = 0; less = 0;
        // flip the sign bit if comparison is signed (option_bits_in[3] = 0)
        sbit1 = option_bits_in[3] ? `RB'b0 : sbit;            // sign bit if signed
        eq = (operand2 & sizemask) == (operand3 & sizemask);  // operands are equal
        less = ((operand2 & sizemask) ^ sbit1) < ((operand3 & sizemask) ^ sbit1); // a < b, signed or unsigned
            
        if (option_bits_in[2:1] == 0) begin
            b1 = eq;              // a == b
        end else if (option_bits_in[2:1] == 1) begin
            b1 = less;            // a < b
        end else if (option_bits_in[2:1] == 2) begin
            b1 = ~less & ~eq;     // a > b
        end else begin
            logic [`RB1:0] absa;
            logic [`RB1:0] absb;
            absa = signbit2 ? -operand2 : operand2;      // abs(a)
            absb = signbit3 ? -operand3 : operand3;      // abs(b)
            b1 = (absa & sizemask) < (absb & sizemask);  // abs(a) < abs(b)
        end        
        jump_result = b1;                                // result for conditional jump
        b2 = b1 ^ option_bits_in[0];                     // bit 0 of condition code inverts the result
        
        // alternative use of mask
        case (option_bits_in[5:4])
        2'b00: b3 = mask_val[0] ? b2 : operand1[0];    // normal fallback
        2'b01: b3 = mask_val[0] & b2 & operand1[0];    // mask & result & fallback
        2'b10: b3 = mask_val[0] & (b2 | operand1[0]);  // mask & (result | fallback)
        2'b11: b3 = mask_val[0] & (b2 ^ operand1[0]);  // mask & (result ^ fallback)
        endcase
        
        if (opx == `II_MIN) begin
            if (option_bits_in[2] & !option_bits_in[3] & (signbit2 | signbit3)) result = 0; // return 0 if either operand is 0
            else result = less ? operand2 : operand3;  // return smallest operand
            
        end else if (opx == `II_MAX) begin
            result = less ? operand3 : operand2;       // return largest operand
            
        end else if (mask_used_in | mask_alternative_in) begin
            // combine result with rest of mask or NUMCONTR
            result = {mask_val[(`MASKSZ-1):1],b3};  // combine result with remaining bits from mask
            
        end else begin
            // normal compare
            result = b3;
        end 

    end else if (opx == `II_ADD || opx == `II_SUB) begin
        // addition, subtraction, and conditional jumps involving addition or subtraction
        logic [`RB:0] bigresult;       // one extra bit on result for carry
        logic zero;                    // result is zero
        logic sign;                    // sign of result
        logic carry;                   // unsigned carry/borrow
        logic overflow;                // signed overflow
        
        if (~opx[0]) bigresult = operand2 + operand3; // add
        else         bigresult = operand2 - operand3; // subtract
        result = bigresult[`RB1:0];    // result without extra carry bit
        
        case (ot_in[1:0])
        0:  begin                      // 8 bit
            sign  = bigresult[7];      // sign bit
            carry = bigresult[8];      // carry out (unsigned overflow)
            end
        1:  begin                      // 16 bit
            sign  = bigresult[15];     // sign bit
            carry = bigresult[16];     // carry out (unsigned overflow)
            end
        2:  begin                      // 32 bit
            sign  = bigresult[31];     // sign bit
            carry = bigresult[32];     // carry out (unsigned overflow)
            end
        3:  begin                      // 64 bit (or 32)
            sign  = bigresult[`RB1];   // sign bit
            carry = bigresult[`RB];    // carry out (unsigned overflow)
            end
        endcase
        zero = ~|(result & sizemask);  // result is zero
        overflow = (signbit2 ^ signbit3 ^ ~opx[0]) & (signbit2 ^ sign); // signed overflow
        
        // jump condition
        case (opj[3:1])
        `IJ_SUB_JZ      >> 1: jump_result = zero;
        `IJ_SUB_JNEG    >> 1: jump_result = sign;
        `IJ_SUB_JPOS    >> 1: jump_result = ~sign & ~zero;
        `IJ_SUB_JOVFLW  >> 1: jump_result = overflow;
        `IJ_SUB_JBORROW >> 1: jump_result = carry;
        default:              jump_result = 0;
        endcase            
        
    end else if (opx == `II_AND || opx == `II_OR || opx == `II_XOR) begin                    
        if (opx == `II_AND) begin
            // bitwise AND, and conditional jumps involving this    
            result = operand2[`RB1:0] & operand3[`RB1:0];            
        end else if (opx == `II_OR) begin
            // bitwise OR, and conditional jumps involving this    
            result = operand2[`RB1:0] | operand3[`RB1:0];        
        end else if (opx == `II_XOR) begin
            // bitwise XOR, and conditional jumps involving this    
            result = operand2[`RB1:0] ^ operand3[`RB1:0];
        end
        jump_result = ~|(result & sizemask);     // zero condition for conditional jump

    end else if (opx >= `II_CLEAR_BIT && opx <= `II_TEST_BITS_OR) begin
        // various bit manipulation instructions
        logic [`RB1:0] onebit;                   // 1 in the position indicated by opr3
        logic rbit;                              // result bit from test
        rbit = 0;
        onebit = 0;
        if ((operand3 & sizemask) <= msb) onebit[operand3[5:0]] = 1'b1;// onebit = 1 ** opr3

        case (opx)
        `II_CLEAR_BIT:      result = operand2 & ~ onebit;
        `II_SET_BIT:        result = operand2 | onebit;
        `II_TOGGLE_BIT:     result = operand2 ^ onebit;
        `II_TEST_BIT:       begin
                                rbit =  |(operand2 & onebit);
                            end
        `II_TEST_BITS_OR:   begin
                                rbit =  |(operand2 & operand3 & sizemask);
                            end
        `II_TEST_BITS_AND:  begin
                                rbit = ~|(((operand2 & operand3) ^ operand3) & sizemask);
                            end
        endcase
        jump_result  = rbit;                           // jump condition for bit tests
        
        if (opx >= `II_TEST_BIT && opx <= `II_TEST_BITS_OR) begin
            // alternative use of mask and fallback in bit test instructions
            logic a, b, c;
            a = mask_val[0] ^ option_bits_in[4];    // mask bit flipped by option bit 4
            b = rbit ^ option_bits_in[2];              // result bit flipped by option bit 2
            c = operand1[0] ^ option_bits_in[3];       // fallback bit flipped by option bit 3
            case (option_bits_in[1:0])                 // boolean operations controlled by option bits 1-0
            2'b00: result[0] = a ?  b : c;             // normal fallback
            2'b01: result[0] = a & (b & c);            // mask & result & fallback
            2'b10: result[0] = a & (b | c);            // mask & (result | fallback)
            2'b11: result[0] = a & (b ^ c);            // mask & (result ^ fallback)
            endcase
            if (option_bits_in[5]) begin               // copy remaining bits from mask or NUMCONTR
                result[`RB1:1] = mask_val[(`MASKSZ-1):1];
            end
        end
     
    end else if ((opx >= `II_SHIFT_LEFT && opx <= `II_SHIFT_RIGHT_U) || opx == `II_FUNNEL_SHIFT
        || opx == `IX_MOVE_BITS1 || opx == `IX_MOVE_BITS2) begin
        // shift instructions and other instruction involving shift and rotate
        
        // Barrel shifters are expensive in terms of LUT use.
        // Make one universal barrel shifter to use for all shift and rotate instructions
        logic [(`RB*2-1):0] barrel;         // input to barrel shifter. 2x32 or 2x64 bits        
        logic [`RB1:0] barrel_out;          // output from barrel shifter. 32 or 64 bits        
        logic [5:0] shift_count1;           // shift count for barrel shifter
        logic [5:0] shift_count2;           // shift count for barrel shifter, limited
        logic overfl;                       // shift count overflows
        if (opx == `II_SHIFT_LEFT || opx == `II_ROTATE) begin
            shift_count1 = -operand3[5:0];
        end else begin
            shift_count1 =  operand3[5:0];
        end
        
        // select input for barrel shifter
        barrel = 0;        
        if (ot_in[1:0] == 0) begin // 8 bits
            shift_count2 = shift_count1[2:0]; 
            if (opx == `II_SHIFT_LEFT || opx == `IX_MOVE_BITS1) begin
                barrel[15:8] = operand2[7:0];
                if (operand3[5:0] == 0) barrel[7:0] = operand2[7:0]; // no shift
            end else if (opx == `II_SHIFT_RIGHT_S) begin
                barrel[7:0]  = operand2[7:0];
                barrel[15:8] = {8{operand2[7]}}; // sign bit
            end else if (opx == `II_SHIFT_RIGHT_U || opx == `IX_MOVE_BITS2) begin
                barrel[7:0]  = operand2[7:0];
            end else if (opx == `II_ROTATE) begin
                barrel[7:0]  = operand2[7:0];
                barrel[15:8] = operand2[7:0];
            end else begin // funnel shift
                barrel[7:0]  = operand1[7:0];
                barrel[15:8] = operand2[7:0];
            end
        end else if (ot_in[1:0] == 1) begin // 16 bits
            shift_count2 = shift_count1[3:0]; 
            if (opx == `II_SHIFT_LEFT || opx == `IX_MOVE_BITS1) begin
                barrel[31:16] = operand2[15:0];
                if (operand3[5:0] == 0) barrel[15:0] = operand2[15:0]; // no shift                
            end else if (opx == `II_SHIFT_RIGHT_S) begin
                barrel[15:0]  = operand2[15:0];
                barrel[31:16] = {16{operand2[15]}}; // sign bit
            end else if (opx == `II_SHIFT_RIGHT_U || opx == `IX_MOVE_BITS2) begin
                barrel[15:0]  = operand2[15:0];
            end else if (opx == `II_ROTATE) begin
                barrel[15:0]  = operand2[15:0];
                barrel[31:16] = operand2[15:0];
            end else begin // funnel shift
                barrel[15:0]  = operand1[15:0];
                barrel[31:16] = operand2[15:0];
            end
        end else if (ot_in[1:0] == 2 || `RB <= 32) begin // 32 bits (or 64 bits if not supported) 
            shift_count2 = shift_count1[4:0]; 
            if (opx == `II_SHIFT_LEFT || opx == `IX_MOVE_BITS1) begin
                barrel[63:32] = operand2[31:0];
                if (operand3[5:0] == 0) barrel[31:0] = operand2[31:0]; // no shift                
            end else if (opx == `II_SHIFT_RIGHT_S) begin
                barrel[31:0]  = operand2[31:0];
                barrel[63:32] = {32{operand2[31]}}; // sign bit
            end else if (opx == `II_SHIFT_RIGHT_U || opx == `IX_MOVE_BITS2) begin
                barrel[31:0]  = operand2[31:0];
            end else if (opx == `II_ROTATE) begin
                barrel[31:0]  = operand2[31:0];
                barrel[63:32] = operand2[31:0];
            end else begin // funnel shift
                barrel[31:0]  = operand1[31:0];
                barrel[63:32] = operand2[31:0];
            end
        end else begin // 64 bits (if supported)
            shift_count2 = shift_count1[5:0]; 
            if (opx == `II_SHIFT_LEFT || opx == `IX_MOVE_BITS1) begin
                barrel[127:64] = operand2[63:0];
                if (operand3[5:0] == 0) barrel[63:0] = operand2[63:0]; // no shift                
            end else if (opx == `II_SHIFT_RIGHT_S) begin
                barrel[63:0]   = operand2[63:0];
                barrel[127:64] = {64{operand2[63]}}; // sign bit
            end else if (opx == `II_SHIFT_RIGHT_U || opx == `IX_MOVE_BITS2) begin
                barrel[63:0]  = operand2[63:0];
            end else if (opx == `II_ROTATE) begin
                barrel[63:0]  = operand2[63:0];
                barrel[127:64] = operand2[63:0];
            end else begin // funnel shift
                barrel[63:0]   = operand1[63:0];
                barrel[127:64] = operand2[63:0];
            end
        end
        
        // big barrel shifter
        barrel_out = barrel[shift_count2+:`RB];
        
        // select output
        overfl = (operand3 & sizemask) > msb; // check if shift count overflows
        
        if (opx == `IX_MOVE_BITS1 || opx == `IX_MOVE_BITS2) begin   // move_bits instruction
            // insert shift result in destination bit field
            integer i;
            for (i = 0; i < `RB; i++) begin
                if (i >= im4_bits_in[13:8] && i <= option_bits_in) result[i] = barrel_out[i];
                else result[i] = operand1[i];
            end
        
        end else if (overfl) begin
            if (opx == `II_SHIFT_RIGHT_S) result = {`RB{signbit2}}; // shift right overflows to sign bit
            else if (opx == `II_ROTATE) result = barrel_out;        // rotate has no overflow
            else result = 0;                                        // all other shifts overflow to zero
            
        end else begin
            result = barrel_out;  // result of shift or rotate        
        end

 
    end else if (opx == `II_ADD_ADD) begin
        // 3-operand add. signs are controlled by option bits
        // (this is separate from the add and subtract operations with conditional jumps because the timing is critical)
        logic [`RB1:0] r1, r2, r3;
        r1 = option_bits_in[0] ? -operand1[`RB1:0] : operand1[`RB1:0];
        r2 = option_bits_in[1] ? -operand2[`RB1:0] : operand2[`RB1:0];
        r3 = option_bits_in[2] ? -operand3[`RB1:0] : operand3[`RB1:0];
        result = r1 + r2 + r3;
        
    end else if (opx == `II_SELECT_BITS) begin
        // select_bits instruction    
        result = (operand1[`RB1:0] & operand3[`RB1:0]) | (operand2[`RB1:0] & ~operand3[`RB1:0]);
    
    // bit scan is critical in terms of timing. Several different implementations tried here:
    `define BITSCAN_BASED_ON_ROUNDP2       
    `ifdef  BITSCAN_BASED_ON_ROUNDP2   // bit scan and roundp2 instructions combined. This takes less resources

    end else if (opx == `IX_BIT_SCAN || opx == `IX_ROUNDP2) begin
        // 
        // using bit index method because this makes roundp2 simple
        
        logic [`RB1:0] a;              // intermediate results
        logic [`RB1:0] b;
        logic [`RB1:0] c;
        logic [`RB1:0] d;
        logic [6:0]    bitscan_result;
        logic [5:0]    r;
        logic          iszero;         // input is zero
        logic          ispow2;         // input is a power of 2
        r = 0; iszero = 0;
        
        a = operand2 & sizemask;
        ispow2 = ~|(a & (a-1));        // a is a power of 2
        
        if (opx == `IX_ROUNDP2 || operand3[0]) begin
            // bitscan reverse scan
            `ifdef SUPPORT_64BIT
                b = reversebits64(a);  // reverse order of bits (in subfunctions.vh)
                c = b & ~(b-1);        // isolate lowest 1-bit
                d = reversebits64(c);  // reverse back again
            `else
                b = reversebits32(a);  // reverse order of bits (in subfunctions.vh)
                c = b & ~(b-1);        // isolate lowest 1-bit
                d = reversebits32(c);  // reverse back again            
            `endif
        end else begin
            // bitscan forward scan
            d = a & ~(a-1);            // isolate lowest 1-bit
        end
        
        // bitindex implemented in subfunctions.vh
        bitscan_result = bitindex(d);
        r = bitscan_result[6:1];
        iszero = bitscan_result[0];
        
        if (iszero) begin              // input is zero. output determined by option bit 1
            if (operand3[4]) begin
                result = ~(`RB'b0);    // return -1 if zero
            end else begin
                result = `RB'b0;       // return 0 if zero
            end
        end else if (opx == `IX_BIT_SCAN) begin
            result = r;                // output result
        end else if (!operand3[0] || ispow2) begin
            // roundp2 round down to nearest power of 2
            result = d;
        end else begin
            // round up to nearest power of 2
            if (signbit2) begin        // overflow
                result = operand3[5] ? ~(`RB'b0) : 0; // return 0 or -1 if overflow
            end else begin
                result = {d,1'b0};     // round up
            end 
        end
        
    `else   // bit scan and roundp2 instructions implemented separately
    
    end else if (opx == `IX_ROUNDP2) begin
        
        logic [`RB1:0] a;              // intermediate results
        logic [`RB1:0] b;
        logic [`RB1:0] c;
        logic [`RB1:0] d;
        logic          iszero;         // input is zero
        logic          ispow2;         // input is a power of 2
        
        a = operand2 & sizemask;       // cut off input to desired operand size
        iszero = ~|a;                  // input is zero
        ispow2 = ~|(a & (a-1));        // input is a power of 2
    
        `ifdef SUPPORT_64BIT
            b = reversebits64(a);      // reverse order of bits (in subfunctions.vh)
            c = b & ~(b-1);            // isolate lowest 1-bit
            d = reversebits64(c);      // reverse back again
        `else
            b = reversebits32(a);      // reverse order of bits (in subfunctions.vh)
            c = b & ~(b-1);            // isolate lowest 1-bit
            d = reversebits32(c);      // reverse back again            
        `endif
    
        if (iszero) begin              // input is zero. output determined by option bit 4
            if (operand3[4]) begin
                result = ~(`RB'b0);    // return -1 if zero
            end else begin
                result = 0;            // return 0 if zero
            end
        end else if (~operand3[0] | ispow2) begin
            // roundp2 round down to nearest power of 2
            result = d;
        end else begin
            // round up to nearest power of 2
            if (signbit2) begin        // overflow
                result = operand3[5] ? ~(`RB'b0) : 0; // return 0 or -1 if overflow
            end else begin
                result = {d,1'b0};     // round up
            end 
        end

    end else if (opx == `IX_BIT_SCAN) begin
    
        logic [`RB1:0] a;              // input cut off to desired operand size
        logic [`RB1:0] b;              // input with bits reversed
        logic [`RB1:0] c;              // input bits reversed if forward scan
        logic [6:0]    r;              // bitscan result
        logic          iszero;         // input is zero
        
        a = operand2 & sizemask;       // cut off input to desired operand size
        
        // reverse bits if forward scan
        case (ot_in[1:0])
        0:  b = reversebits8(operand2[7:0]);         // 8 bit
        1:  b = reversebits16(operand2[15:0]);       // 16 bit
        `ifdef SUPPORT_64BIT
        3:  b = reversebits64(operand2[63:0]);       // 64 bit
        `endif
        default: b = reversebits32(operand2[31:0]);  // 32 bit
        endcase

        if (operand3[0]) c = a;        // reverse scan
        else             c = b;        // forward scan        
        
        // bitscan function defined in subfunctions.vh
        r = bitscan64A(a);             // this implementation may be faster?
        //r = bitscan64C(c);           // alternative implementation
        iszero = r[0];                 // input is zero
        
        if (iszero) begin              // input is zero. output determined by option bit 4
            if (operand3[4]) begin
                result = ~(`RB'b0);    // return -1 if zero
            end else begin
                result = 0;            // return 0 if zero
            end
        end else begin
            result = r[6:1];           // normal bitscan result
        end
    
    `endif  


    end else if (opx == `IX_POPCOUNT) begin
        // popcount instruction. functions are is in subfunctions.vh
        if (`RB <= 32) result = popcount32(operand2 & sizemask);
        else result = popcount64(operand2 & sizemask);
        
    end else if (opx == `IX_ABS) begin
        // abs instruction
        if (~signbit2) begin
            result = operand2;       // input is not negative
        end else if ((operand2 & ~sbit & sizemask) == 0) begin
            // overflow
            case (operand3[1:0])     // last operand determines what to do with overflow
            0: result = operand2;    // overfloaw wraps around
            1: result = ~sbit;       // overfloaw gives saturation
            2: result = 0;           // overflow gives 0
            endcase
        end else begin
            result = -operand2;      // input is negative. change sign
        end
        
    end else if (opx == `IX_TRUTH_TAB3) begin
        // truth_tab3 instruction
        // truth_table_lookup is in subfunctions.vh
        result = truth_table_lookup(operand1, operand2, operand3, im4_bits_in[7:0]);
        if (option_bits_in[0]) result[`RB1:1] = 0;   // output only bit 0
        else if (option_bits_in[1]) result[`RB1:1] = mask_val[(`MASKSZ-1):1]; // remaining bits from mask

    end else if (opx == `IX_INSERT_HI) begin    
        // insert constant into high 32 bits, leave low 32 bit unchanged
        `ifdef SUPPORT_64BIT
            result = {operand3[31:0],operand2[31:0]};
        `else
            result = operand2;
        `endif        
 
    end else if (category_in == `CAT_JUMP) begin
        // jump instructions that have no corresponding general instruction
        
        if (opj[5:0] >= `IJ_INC_COMP_JBELOW && opj[5:0] <= `IJ_INC_COMP_JABOVE+1) begin
            // loop instruction: increment and jump if below/above
        
        `ifdef THIS_VERSION_IS_SLOW__IT_IS_NOT_USED
            // This version is slow because the addition and the compare both involve a big carry-lookahead circuit.
            // Use this version only if timing is not critical 
            logic eq, less;            
            result = operand2 + 1;     // increment           
            eq = (result & sizemask) == (operand3 & sizemask);  // operands are equal
            less = ((result & sizemask) ^ sbit) < ((operand3 & sizemask) ^ sbit); // a+1 < b, signed
            if (opj[1]) begin
                jump_result = ~less & ~eq;   // above
            end else begin
                jump_result = less;          // below
            end
        `else
            // This version is faster because it does most of the compare in parallel with the addition
            logic less;                // a < b, signed
            logic result_equal_limit;  // a + 1 == b
            logic b_is_min;            // the limit b is INT_MIN. a+1 < b always false
            logic overflow1;           // a+1 overflows
            // The overflow check may not be important, but we want to make sure that the result is always
            // the same as if the increment and the compare are coded as two separate instructions
            result = operand2 + 1;     // increment           
            less = ((operand2 & sizemask) ^ sbit) < ((operand3 & sizemask) ^ sbit); // a < b, signed
            overflow1 = ((operand2 & sizemask) ^ sbit) == sizemask;       // a+1 overflows
            b_is_min = ((operand3 & sizemask) ^ sbit) == 0;               // limit is INT_MIN, nothing is less than limit
            result_equal_limit = ((result ^ operand3) & sizemask) == 0;   // a + 1 == b
            if (opj[1]) begin          // increment_compare/jump_above
                // check if a+1 > b <=> !(a+1 <= b) <=> !(a < b || overflow)
                jump_result = ~(less | overflow1);  // a+1 > b
            end else begin    // increment_compare/jump_below
                // check if a+1 < b <=> (a < b && a+1 != b) || (overflow && b != INT_MIN) 
                jump_result = (less & ~result_equal_limit) | (overflow1 & ~b_is_min);  // a + 1 < b
            end
        
        `endif
            
        end else if (opj[5:1] == `IJ_SUB_MAXLEN_JPOS >> 1) begin
        
            // vector loop instruction: subtract maximum vector length and jump if positive
            logic [`RB1:0] max_vector_length;
            logic sign;                     // sign of result
            logic zero;                     // result is zero
            if (`NUM_VECTOR_UNITS > 0) max_vector_length = `NUM_VECTOR_UNITS * 8;
            else max_vector_length = 8;     // make sure max_vector_length is not zero to avoid infinite loop
            result = operand2 - max_vector_length;
            
            zero = ~|(result & sizemask);            
            case (ot_in[1:0])
            0:  sign = result[7];           // 8 bit
            1:  sign = result[15];          // 16 bit
            2:  sign = result[31];          // 32 bit
            3:  sign = result[`RB1];        // 64 bit (or 32)
            endcase            
            `ifdef SUPPORT_64BIT
            if (instruction_in[`IL] == 1) begin
                // 64 bits in format C
                otout = 3;                  // 64 bit output
                sign = result[`RB1];
                zero = ~|result;
            end
            `endif
            jump_result = ~sign & ~zero;
            
        end        
        
    end else if (opx == `II_NOP | opx == `II_PREFETCH) begin
        // nop instruction. do nothing

    end else begin    
        // unknown instruction. error
        error = 1;
        
    end
    
    if (vector_in) error = 1;  // Vector instructions not supported yet
    
    if (category_in == `CAT_JUMP) begin
    
        // manage conditional jump conditions
        
        logic [1:0] il;
        logic [2:0] mode;
        il = instruction_in[`IL];
        mode = instruction_in[`MODE];
        
        // calculate target if not jumping
        //instruction_length = il[1] ? il : 1;  // il cannot be 0 for jump instructions)
        nojump_target = instruction_pointer_in + il;
        // treat jump as not taken if jump target is equal to nojump target
        jump_not_taken = nojump_target == operand1_in;
        
        // detect jump result
        if (jump_result ^ opj[0]) jump_taken = 1;        // bit 0 of opj inverts the condition
        
        if (opj > `IJ_LAST_CONDITIONAL) jump_taken = 1;  // unconditional jump always taken
        
        if (opj == `IJ_TRAP) begin // trap and IJ_SYSCALL have same opj. Both will stop debugger
            jump_taken = 0;        // use trap as debug breakpoint. Resume execution in next instruction
        end 
        
        // compare, test and indirect jumps have no register return. The decoder takes care of result_type = `RESULT_NONE;
    end
    
    // normal register output
    // mask_used_in removed from this equation because of critical timing:
    normal_output = valid_in & ~stall 
    & (result_type == `RESULT_REG | result_type == `RESULT_SYS) 
    & (mask_val[0] | mask_alternative_in) & ~vector_in;
    
end


// outputs
always_ff @(posedge clock) if (clock_enable) begin
    if (normal_output) begin
        // normal register output
        case (otout)
        0: result_out <= result[7:0];
        1: result_out <= result[15:0];
        2: result_out <= result[31:0];
        3: result_out <= result[`RB1:0];
        endcase
        register_write_out <= (tag_val_in != tag_val_out) & ~reset; // avoid repeating the same output
        // destination register number. high bit is 1 for system registers
        register_a_out <= {result_type[0],instruction_in[`RD]};

    end else if (!valid_in || stall || result_type == `RESULT_MEM || result_type == `RESULT_NONE || vector_in) begin
        // note: the FPGA has no internal tri-state buffers. We need to simulate result bus by or'ing outputs 
        register_write_out <= 0;
        result_out <= 0;
        register_a_out <= 0;

    end else begin
        // mask is zero. output is fallback
        case (otout)
        0: result_out <= operand1[7:0];
        1: result_out <= operand1[15:0];
        2: result_out <= operand1[31:0];
        3: result_out <= operand1[`RB1:0];
        endcase
        register_write_out <= (tag_val_in != tag_val_out) & ~reset; // avoid repeating the same output
        register_a_out <= {1'b0,instruction_in[`RD]};        
    end 
    
    if (stall | !valid_in) tag_val_out <= 0;
    else tag_val_out <= tag_val_in;   // output tag_val to release tag even if no register    
    
    if (stall || !valid_in) begin
        jump_out <= 0;
        nojump_out <= 0;        
    end else if (category_in == `CAT_JUMP) begin
        // additional output for conditional jump instructions
        if (jump_not_taken | ~jump_taken) begin
            jump_out <= 0;
            nojump_out <= valid_in;
            jump_pointer_out <= nojump_target;
        end else begin // jump taken
            jump_out <= valid_in && !reset;
            nojump_out <= 0;
        end
    end else begin
        // not a jump instruction
        jump_out <= 0;
        nojump_out <= 0;
        jump_pointer_out <= 0;
    end
    
    // special cases for indirect jumps
    if (opx == `IX_INDIRECT_JUMP) begin
        jump_pointer_out <= operand3[`RB1:2] - {1'b1,{(`CODE_ADDR_START-2){1'b0}}}; // jump target = (last operand - code memory start)/ 4
        //if (|(operand3[1:0])) error_parm_out <= 1;    // misaligned jump target. handled above
        
    end else if (opx == `IX_RELATIVE_JUMP) begin      // jump target is calculated
        jump_pointer_out <= relative_jump_target;

    end else begin
        jump_pointer_out <= operand1_in;              // jump target is calculated in previous stage
    end

    // error outputs
    error_out <= error & valid_in & !reset;           // unknown instruction   
    error_parm_out <= error_parm & valid_in & !reset; // wrong parameter   

    // other outputs
    valid_out <= !stall & valid_in & !reset;          // a valid output is produced
    stall_out <= stall  & valid_in & !reset;          // stalled. waiting for operand
    //stall_next_out <= stall_next & valid_in & !reset; // predict stall in next clock cycle
    stall_next_out <= stall_next & valid_in & !reset & tag_val_in != tag_val_out; // predict stall in next clock cycle


    // outputs for debugger:
    debug1_out <= 0;
    
    debug1_out[6:0]   <= opx;    
    debug1_out[14:8]  <= opj;
    
    
    debug1_out[21:20] <= category_in;
    
    debug1_out[24]    <= stall;
    debug1_out[25]    <= stall_next;
    debug1_out[27]    <= error;
    
    debug1_out[28]    <= jump_taken;
    debug1_out[29]    <= jump_not_taken;
    debug1_out[30]    <= jump_result;
    debug1_out[31]    <= valid_in;    
    
    
    debug2_out[16]    <= opr1_used_in;     
    debug2_out[17]    <= opr2_used_in;     
    debug2_out[18]    <= opr3_used_in;     
    debug2_out[19]    <= mask_used_in;     
    debug2_out[20]    <= mask_alternative_in;     
    debug2_out[21]    <= mask_off;

    //debug2_out[31]    <= &instruction_in & ot_in[2] & &(im4_bits_in[15:14]); // prevent warnings for unused inputs
end

endmodule
