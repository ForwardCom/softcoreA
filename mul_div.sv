//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2021-06-06
// Last modified:  2022-12-25
// Module Name:    mul_div
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Arithmetic-logic unit for multiplication and division
// of general purpose registers.
//////////////////////////////////////////////////////////////////////////////////

`include "defines.vh"

module mul_div (
    input clock,                            // system clock
    input clock_enable,                     // clock enable. Used when single-stepping
    input reset,                            // system reset
    input valid_in,                         // data from previous stage ready
    input [31:0] instruction_in,            // current instruction, up to 3 words long. Only first word used here
    input [`TAG_WIDTH-1:0] tag_val_in,      // instruction tag value    
    input [6:0] opx_in,                     // operation ID in execution unit. mostly equal to op1
    input [2:0] ot_in,                      // operand type
    input [5:0] option_bits_in,             // option bits from IM5 or mask
    input div_predict_in,                   // a division instruction is underway from the address generator stage
     
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
    output reg [4:0] register_a_out,        // register to write
    output reg [`RB1:0] result_out,         // 
    output reg [`TAG_WIDTH-1:0] tag_val_out,// instruction tag value
    output reg [`TAG_WIDTH-1:0] predict_tag2_out,// predict tag for bus2_value in next clock cycle
    output reg div_out,                     // current output is a division result
    output reg stall_out,                   // waiting for an operand or not ready to receive a new instruction
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
logic signbit2, signbit3;                   // sign bits of three operands
logic [6:0]  opx;                           // operation ID in execution unit
logic mask_off;                             // result is masked off
logic fasttrack;                            // mask = 0 or div by 0, result can be delivered immediately
logic slowtrack;                            // mask = 0 or div by 0, but result bus not vacant. result goes through multiplication pipeline
logic valid;                                // instruction is valid
logic stall;                                // waiting for operands
logic stall_next;                           // will be waiting for operands in next clock cycle
logic error;                                // unknown instruction
logic error_parm;                           // wrong parameter for instruction
logic [`RB1:0] sizemask;                    // mask for operand type


// ***** variables for multiplication *****
logic start_mul;                            // start multiplication pipeline
logic high_mul;                             // get high part of multiplication result
`ifdef SUPPORT_64BIT 
`define MAX_MUL_BITS   64                   // maximum multiplication size
`else
`define MAX_MUL_BITS   32                   // maximum multiplication size
`endif
// NOTE: do not set MAX_MUL_BITS < max division size because then slowtrack mechanism will fail!

// multiplication. The number of multiplication pipeline steps may depend on the FPGA type:
`define MUL_STEPS       3                   // works with 3 steps in 32x32 -> 64 bit multiplication. using 3 DSPs
//`define MUL_STEPS     3                   // also works with 3 steps in 64x64 -> 128 bit multiplication. using 16 DSPs
reg [`MAX_MUL_BITS-1:0] mulA;               // first multiplicand
reg [`MAX_MUL_BITS-1:0] mulB;               // second multiplicand
reg [`MAX_MUL_BITS*2-1:0] mulProd [`MUL_STEPS-1:0]; // pipelined product
reg [`MUL_STEPS:0] mulLine;                 // indicates progress stage
reg [4:0] destination_reg [`MUL_STEPS:0];   // destination register
reg [`TAG_WIDTH-1:0] tag_val [`MUL_STEPS:0];// destination tag 
reg [1:0] operand_type [`MUL_STEPS:0];      // operand type for result
reg [`MAX_MUL_BITS-1:0] mul_addend [`MUL_STEPS:0]; // value to add to multiplication result for MUL_ADD or signed high multiplication
reg [`MUL_STEPS:0] mul_high_line;           // use high part of multiplication result
reg [`TAG_WIDTH-1:0] last_tag;              // tag value of last instruction
integer i;                                  // loop counter for multiplication pipeline


// ***** variables for division *****
logic start_div;                            // start division
logic signed_dision;                        // division is signed
logic [`RB1:0] div_A0;                      // abs(dividend)
logic [`RB1:0] div_B0;                      // abs(divisor)
logic [`RB1:0] div_result;                  // final result of div or rem
logic end_div;                              // division ending this clock cycle
logic end_div_next;                         // division ending next clock cycle
logic div_zero;                             // division by zero
logic div_rounding;                         // rounding adjustment to div result
logic wait_result_bus;                      // division result ready, waiting for result bus vacant
logic wait_result_bus_next;                 // division result ready next, predict waiting for result bus vacant

reg   div_negative;                         // division result is negative
reg   div_busy;                             // division loop is running
reg   div_rem;                              // division to calculate remainder
reg   div_loop;                             // division loop has started
reg   div_finished;                         // division loop has finished
reg   [4:0] div_register;                   // destination register for division
reg   [`TAG_WIDTH-1:0] div_tag;             // destination tag for division
reg   [1:0] div_options;                    // option bits for division
reg   [5:0] div_counter;                    // loop counter for division
reg   [1:0] div_optype;                     // operand type for division
reg   [`RB1:0] div_A;                       // dividend in loop
reg   [`RB1:0] div_B;                       // divisor in loop
reg   [`RB1:0] div_R;                       // division intermediate result in loop
reg   [`RB1:0] div_B00;                     // save divisor to use for rounding result


always_comb begin

    // operand type:
    case (ot_in[1:0])
    0: begin 
        //msb = 7;   // 8 bit
        sizemask = 8'HFF;
        signbit2 = operand2[7];
        signbit3 = operand3[7];
        end
    1: begin
        //msb = 15;   // 16 bit
        sizemask = 16'HFFFF;
        signbit2 = operand2[15];
        signbit3 = operand3[15];
        end           
    2: begin
        //msb = 31;   // 32 bit
        sizemask = 32'HFFFFFFFF;
        signbit2 = operand2[31];
        signbit3 = operand3[31];        
        end
    3: begin
        //msb = `RB1;   // 64 bit if supported
        sizemask = ~(`RB'b0);        
        signbit2 = operand2[`RB1];
        signbit3 = operand3[`RB1];
        end
    endcase

    // get all input operands
    stall = 0;
    stall_next = 0;    
    operand1 = 0;    
    operand2 = 0;
    operand3 = 0;
    mask_val = 0;
    mask_off = 0;    
          
    if (valid_in) begin

        if (mask_val_in[`MASKSZ]) begin      // value missing
            if (write_en1 & mask_val_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
                mask_val = writeport1_in[(`MASKSZ-1):0]; // obtained from result bus 1
            end else if (write_en2 & mask_val_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
                mask_val = writeport2_in[(`MASKSZ-1):0]; // obtained from result bus 2 (which may be my own output)
            end else begin
                if (mask_used_in) begin
                    stall = 1;                  // operand not ready
                    if (mask_val_in[`TAG_WIDTH-1:0] != predict_tag1_in 
                    & mask_val_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                        stall_next = 1;         // operand not ready in next clock cycle
                    end
                end                 
            end
        end else begin                          // value available
           mask_val = mask_val_in;
        end
        
        mask_off = mask_used_in & mask_val[`MASKSZ] == 0 & mask_val[0] == 0; // result is masked off.        

        if (operand1_in[`RB]) begin             // value missing
            if (write_en1 & operand1_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
                operand1 = writeport1_in;       // obtained from result bus 1
            end else if (write_en2 & operand1_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
                operand1 = writeport2_in;       // obtained from result bus 2 (which may be my own output)
            end else begin
                if (opr1_used_in) begin
                    stall = 1;                  // operand not ready
                    if (operand1_in[`TAG_WIDTH-1:0] != predict_tag1_in & operand1_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                        stall_next = 1;         // operand not ready in next clock cycle
                    end                 
                end
            end
        end else begin
            operand1 = operand1_in[`RB1:0];
        end 

        if (opr2_from_ram_in) begin
            operand2 = ram_data_in;        
        end else if (operand2_in[`RB]) begin    // value missing
            if (write_en1 & operand2_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
                operand2 = writeport1_in;       // obtained from result bus 1
            end else if (write_en2 & operand2_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
                operand2 =  writeport2_in;      // obtained from result bus 2 (which may be my own output)
            end else begin
                if (opr2_used_in & !mask_off) begin
                    stall = 1;                  // operand not ready
                    if (operand2_in[`TAG_WIDTH-1:0] != predict_tag1_in & operand2_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                        stall_next = 1;         // operand not ready in next clock cycle
                    end                 
                end
            end 
        end else begin                          // value available
            operand2 = operand2_in[`RB1:0];
        end
             
        if (opr3_from_ram_in) begin
            operand3 = ram_data_in;        
        end else if (operand3_in[`RB]) begin    // value missing
            if (write_en1 & operand3_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
                operand3 = writeport1_in;       // obtained from result bus 1
            end else if (write_en2 & operand3_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
                operand3 = writeport2_in;       // obtained from result bus 2 (which may be my own output)
            end else begin
                if (opr3_used_in & !mask_off) begin
                    stall = 1;                  // operand not ready
                    if (operand3_in[`TAG_WIDTH-1:0] != predict_tag1_in & operand3_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                        stall_next = 1;         // operand not ready in next clock cycle
                    end                 
                end
            end
        end else begin                          // value available
            operand3 = operand3_in[`RB1:0];
        end
    
    end
    
    // a second div instruction must be stalled until this one is finished: 
    if (div_predict_in & (start_div | (div_busy & !end_div))) stall_next = 1;   
    // don't put tag_val_in != div_tag here: it may skip a stalled instruction:
    if ((opx >= `II_DIV & opx <= `II_REM_U) & div_busy & valid_in) stall_next = 1;
    //if ((opx >= `II_DIV & opx <= `II_REM_U) & div_predict_in & valid_in) stall_next = 1;
    
    opx = opx_in; 
    error = 0;
    error_parm = 0;
    
    div_zero = opx >= `II_DIV & opx <= `II_REM_U & (operand3 & sizemask) == 0; // division by zero
    signed_dision = opx == `II_DIV | opx == `II_REM;
    
    // result is known immediately if mask is zero or if dividing by zero.
    // fast track: return result immediately if the result bus is vacant
    fasttrack = mask_off & !stall & !mulLine[`MUL_STEPS] & !div_finished;
    // slow track: result is known immediately but result bus not vacant. 
    // send result through multiplication pipeline
    slowtrack = mask_off & !stall & (mulLine[`MUL_STEPS] | div_finished) | (div_zero & !stall);
   
     
    ////////////////////////////////////////////////
    //             Select ALU operation
    ////////////////////////////////////////////////
     
    start_mul = 0;                               // start some kind of multiplication
    high_mul = 0;
    start_div = 0;                               // start division or remainder
    div_A0 = 0;
    div_B0 = 0;
    valid = 0;   
     
    if (opx == `II_MUL | opx == `II_MUL_ADD | opx == `II_MUL_ADD2 | opx == `II_MUL_HI | opx == `II_MUL_HI_U | slowtrack) begin
        // start some kind of multiplication,
        // or sending slowtrack result through multiplication pipeline if result bus is blocked
        if (ot_in >= `OT_INT64 & `MAX_MUL_BITS < 64 & `RB > 32 & !mask_off) error = 1;  // check if 64 bit multiplication is supported
        // NOTE: slowtrack for division will fail if 64 bit division supported, but 64 bit multiplication is not
        if (opx == `II_MUL_HI | opx == `II_MUL_HI_U) high_mul = 1; // high multiplication
        //valid = valid_in & tag_val_in != tag_val[0];  // avoid executing same instruction twice
        valid = valid_in & tag_val_in != last_tag;  // avoid executing same instruction twice
        start_mul = valid & !stall & !fasttrack; // start new multiplication

    end else if (opx >= `II_DIV & opx <= `II_REM_U) begin
        // start division
        div_A0 = ((signbit2 & signed_dision) ? -operand2 : operand2) & sizemask; // abs(dividend)
        div_B0 = ((signbit3 & signed_dision) ? -operand3 : operand3) & sizemask; // abs(divisor)
        // avoid executing same instruction twice
        if (mask_off | div_zero) begin  // fasttrack or slowtrack
            valid = valid_in & tag_val_in != last_tag;        
        end else begin  // normal division
            valid = valid_in & tag_val_in != div_tag;
            start_div = valid; // start new division        
        end

    end else begin    
        error = 1;  // unknown instruction         
    end

    div_rounding = 0;
    if (div_rem) begin  // remainder
        // apply sign to remainder
        div_result = div_negative ? -div_A : div_A;
    end else begin  // division
        // get rounding mode
        if (div_options[1:0] == 2'b01) begin // round down, floor
            div_rounding = div_negative & div_A != 0;  // adjust by 1 if negative and remainder != 0
        end else if (div_options[1:0] == 2'b10) begin // round up, ceil
            div_rounding = !div_negative & div_A != 0;  // adjust by 1 if positive and remainder != 0
        end else if (div_options[1:0] == 2'b11) begin // round to nearest or even
            if (div_A > div_B00[`RB1:1]) div_rounding = 1;  // remainder*2 > divisor: round up
            if (div_A == div_B00[`RB1:1]) div_rounding = div_R[0] & ~div_B00[0];  // remainder*2 == divisor: round up if odd
            
        end else begin // truncate
            div_rounding = 0;
        end
        if (div_negative) div_result = -div_R - div_rounding;
        else div_result = div_R + div_rounding;
    end

    end_div = div_finished & !(mulLine[`MUL_STEPS]);  // division ending this clock cycle and result bus vacant
    end_div_next = div_counter == 0 & div_loop & !(mulLine[`MUL_STEPS-1]);  // division ending next clock cycle and result bus vacant
    
    wait_result_bus = div_finished & mulLine[`MUL_STEPS];  // division result ready, waiting for result bus vacant
    wait_result_bus_next = div_counter == 0 & div_loop & mulLine[`MUL_STEPS-1]; // division result ready next, predict waiting for result bus vacant   
    
end


// Shift registers for pipelined multiplication.
// This should propagate previous values even if new values are stalled.
// Save power in multiplier by disabling if not active
always_ff @(posedge clock) if (clock_enable) begin
    if (reset) begin 
        mulLine <= 0; 
        destination_reg[0] <= 0;
        tag_val[0] <= 0;
        operand_type[0] <= 0;
        mul_high_line <= 0;
        mul_addend[0] <= 0;
        mulA <= 0;
        mulB <= 0;   
        mulProd[0] <= 0;
       
    end else if (|mulLine | start_mul) begin
        // propagate all parameters through shift registers   
        // mulLine is a shift register indicating which clock cycles a result will be available
        mulLine <= {mulLine, (start_mul|slowtrack) & valid_in & tag_val_in != tag_val[0]};
        
        destination_reg[0] <= (start_mul|slowtrack) ? instruction_in[`RD] : 0; // destination register
        operand_type[0] <= ot_in[1:0];
        mul_high_line <= {mul_high_line,high_mul};                 
        for (i = 0; i < `MUL_STEPS; i = i+1) begin
            destination_reg[i+1] <= destination_reg[i];
            tag_val[i+1] <= tag_val[i];
            operand_type[i+1] <= operand_type[i];
            mul_addend[i+1] <= mul_addend[i];
        end
        if (start_mul | slowtrack) begin
            tag_val[0] <= tag_val_in;                  // result tag
        end      
        
        // do pipelined multiplication. 
        // first stage = get operands, (`MUL_STEPS - 1) stages = pipelined multiplication
        // (code example in Vivado Design Suite User Guide ug901-vivado-synthesis.pdf)
        /* False warning in Vivado 2020.1: [DRC DPOP-1] PREG Output pipelining: DSP muldiv_inst/ output muldiv_inst//P[47:0] is not pipelined (PREG=0).
        */
        if (slowtrack) begin
            mulA <= 0;   // slowtrack. Make sure multiplication gives 0, put result value in mul_addend
            mulB <= 0; 
        end else if (opx == `II_MUL_ADD | opx == `II_MUL_ADD2) begin
            mulA <= operand1;
            mulB <= option_bits_in[0] ? -operand2 : operand2; // mul_add instruction has sign of product in option_bits_in[0]
        end else begin
            mulA <= operand2 & sizemask;
            mulB <= operand3 & sizemask;
        end
        mulProd[0] <= mulA * mulB;  // pipelined mulitplication in `MUL_STEPS steps
        for (i = 0; i < `MUL_STEPS - 1; i = i+1) begin
            mulProd[i+1] <= mulProd[i];
        end
        
        // mul_addend is used for four purposes: 
        // 1: fallback value if masked off and slow track is used
        // 2: result of division by zero if slow track is used
        // 3: addend in MUL_ADD instruction, 
        // 4: calculation of signed high multiplication
        if (mask_off) begin
            mul_addend[0] <= operand1; // fallback value if slowtrack
        end else if (div_zero) begin // division by zero        
            if (opx == `II_REM | opx == `II_REM_U) mul_addend[0] <= operand2;  // rem(x/0) = x
            else if (signed_dision &  signbit2)  mul_addend[0] <= ~({1'b0,sizemask[`RB1:1]}); // -1/0 = INT_MIN
            else if (signed_dision & !signbit2)  mul_addend[0] <= {1'b0,sizemask[`RB1:1]}; // +1/0 = INT_MAX
            else                                 mul_addend[0] <= sizemask; // unsigned 1/0 = UINT_MAX            
        end else if (opx == `II_MUL_ADD | opx == `II_MUL_ADD2) begin
            mul_addend[0] <= (option_bits_in[2]) ? -operand3 : operand3;
        end else if (opx == `II_MUL_HI) begin
            // correction for converting unsigned to signed high multiplication
            mul_addend[0] <= - (signbit2 ? operand3 : 0) - (signbit3 ? operand2 : 0);
        end else begin
            mul_addend[0] <= 0;
        end
    end
    
    if (mulLine == 0 & !start_mul & !slowtrack) tag_val[0] <= 0; // keep last tag as long as multiplication is running to avoid executing same instruction twice
    
end


// ***** division and remainder *****
/* This uses a radix-4 division algorithm.
   There may be faster library code available for division in specific FPGA models, but this 
   code is using a general algorithm for the sake of portability and to avoid license problems.
   Step 1: make operands positive, get sign of result, do a coarse shift of the division into a 16-bit range.
   Step 2: shift the divisor into a 2-bit range
   Step 3: division loop. Get two bits of the result for every cycle, subtract from the divisor.
*/
always_ff @(posedge clock) if (clock_enable & (start_div | div_busy | reset)) begin
    if (reset) begin
        div_busy <= 0;
        div_loop <= 0;
        div_counter <= 0;
        div_finished <= 0;
        div_tag <= 0;
    // end else if (start_div & !stall & (!div_busy | end_div)) begin  // end_div makes no difference. end_div_next doesn't work here
    end else if (start_div & !stall & !div_busy) begin
    
        // start division
        div_register <= instruction_in[`RD];  // destination register for division
        div_tag <= tag_val_in;                // destination tag for division
        div_optype <= ot_in;                  // operand type for division
        div_options <= option_bits_in;        // option bits for division
        div_busy <= 1;                        // division has started
        div_loop <= 0;                        // division loop is running
        div_finished <= 0;                    // division loop has finished
        div_rem <= (opx == `II_REM | opx == `II_REM_U); // return remainder rather than quotient
        
        if (opx == `II_DIV) begin
            div_negative <= signbit2 ^ signbit3; // result of division is negative if one operand is negative
        end else if (opx == `II_REM) begin
            div_negative <= signbit2;            // result of modulo is negative if numerator is negative        
        end else begin
            div_negative <= 0;                   // unsigned division or unsigned modulo
        end
        
        div_A <= div_A0;                      // temporary dividend
        div_R <= 0;                           // temporary result
        div_B00 <= div_B0;                    // save divisor
       
       // step 1: make positive and do initial shift into 16-bit ranges
`ifdef SUPPORT_64BIT 
        if (div_A0 >= {div_B0,48'b0}) begin
            div_B <= {div_B0,48'b0};
            div_counter <= 24;
        end else if (div_A0 >= {div_B0,32'b0}) begin
            div_B <= {div_B0,32'b0};
            div_counter <= 16;
        end else 
`endif      
        if (div_A0 >= {div_B0,16'b0}) begin
            div_B <= {div_B0,16'b0};
            div_counter <= 8;
        end else begin
            div_B <= div_B0;
            div_counter <= 0;
        end
    end // no 'else' here if step 1 is pipelined
    
    // step 2: shift into 2-bit ranges
    if (div_busy & !div_loop & !reset & !(div_finished & (mulLine[`MUL_STEPS]))) begin
        if (div_A >= {div_B,14'b0}) begin
            div_B <= {div_B,14'b0};
            div_counter <= div_counter + 7;
        end else if (div_A >= {div_B,12'b0}) begin
            div_B <= {div_B,12'b0};
            div_counter <= div_counter + 6;
        end else if (div_A >= {div_B,10'b0}) begin
            div_B <= {div_B,10'b0};
            div_counter <= div_counter + 5;
        end else if (div_A >= {div_B,8'b0}) begin
            div_B <= {div_B,8'b0};
            div_counter <= div_counter + 4;
        end else if (div_A >= {div_B,6'b0}) begin
            div_B <= {div_B,6'b0};
            div_counter <= div_counter + 3;
        end else if (div_A >= {div_B,4'b0}) begin
            div_B <= {div_B,4'b0};
            div_counter <= div_counter + 2;
        end else if (div_A >= {div_B,2'b0}) begin
            div_B <= {div_B,2'b0};
            div_counter <= div_counter + 1;
        end else begin
            div_B <= div_B;
            div_counter <= div_counter;
        end
        div_loop <= 1;                         // division loop has started

    // step 3: division loop
    end else if (div_loop & !div_finished & !reset) begin
        if (div_A >= (div_B + {div_B,1'b0})) begin
            div_A <= div_A - (div_B + {div_B,1'b0});
            div_R <= {div_R,2'b11}; 
        end else if (div_A >= {div_B,1'b0}) begin
            div_A <= div_A - {div_B,1'b0};
            div_R <= {div_R,2'b10}; 
        end else if (div_A >= div_B) begin
            div_A <= div_A - div_B;
            div_R <= {div_R,2'b01};
        end else begin
            div_A <= div_A;
            div_R <= {div_R,2'b00};
        end
        div_B <= div_B[`RB1:2];
        div_counter <= div_counter - 1;
        if (div_counter == 0) begin 
            div_finished <= 1;
        end
    end else if (end_div) begin
     
        // division finished. result bus vacant
        div_busy <= 0;
        div_loop <= 0;
        div_finished <= 0;
        if (!div_busy) div_tag <= 0; // don't set div_tag to 0 too early because then it may execute same instruction twice
    end

end

// output
always_ff @(posedge clock) if (clock_enable) begin

    stall_out <= 0;
    stall_next_out <= 0;
    register_write_out <= 0;
    result_out <= 0;
    register_a_out <= 0;
    tag_val_out <= 0;
    valid_out <= 0; 
    error_out <= 0;
    error_parm_out <= 0;
    predict_tag2_out <= 0;
    div_out <= 0;
    
    // remember last tag to avoid executing same instruction twice
    if (valid & !stall) last_tag <= tag_val_in;
    if (reset | !valid_in) last_tag <= 0;
    
    if (reset) begin
        register_write_out <= 0;
    end else if (fasttrack & valid & !stall) begin
        // mask is off. result bus is vacant. output fallback value immediately
        //if (mask_off) begin
            result_out <= operand1 & sizemask;       // fallback value if masked off
        /*
        // division by zero does not go through fasttrack because it should not occur in normal
           program code so it is not worth optimizing:
        end else begin  // division by zero
            if (opx == `II_REM | opx == `II_REM_U) result_out <= operand2 & sizemask;        // rem(x/0) = x
            else if (signed_dision &  signbit2) result_out <= (sizemask>>1)+1; // -1 / 0 = INT_MIN
            else if (signed_dision & !signbit2) result_out <= sizemask >> 1; // +1 / 0 = INT_MAX
            else result_out <= sizemask; // unsigned 1 / 0 = UINT_MAX
            
        end*/
        register_write_out <= 1;
        valid_out <= 1;
        register_a_out <= {1'b0,instruction_in[`RD]};
        tag_val_out <= tag_val_in;
    end else if (mulLine[`MUL_STEPS]) begin
        // multiplication result is ready
        register_write_out <= 1;
        valid_out <= 1;
        register_a_out <= {1'b0,destination_reg[`MUL_STEPS]};
        tag_val_out <= tag_val[`MUL_STEPS];
        if (mul_high_line[`MUL_STEPS]) begin
            // high multiplication. mul_addend contains correction if signed    
            case (operand_type[`MUL_STEPS])
            0: begin  // 8 bits
                result_out <= (mulProd[`MUL_STEPS-1][15:8] + mul_addend[`MUL_STEPS]) & 8'hFF;
                end
            1: begin  // 16 bit
                result_out <= (mulProd[`MUL_STEPS-1][31:16] + mul_addend[`MUL_STEPS]) & 16'hFFFF;
                end
            2: begin  // 32 bitss
                result_out <= (mulProd[`MUL_STEPS-1][63:32] + mul_addend[`MUL_STEPS]) & 32'hFFFFFFFF;
                end
            3: begin  // 64 bits
                result_out <= mulProd[`MUL_STEPS-1][`MAX_MUL_BITS*2-1:`MAX_MUL_BITS] + mul_addend[`MUL_STEPS];
                end
            endcase
        end else begin
            // normal multiplication or mul_add or slowtrack
            case (operand_type[`MUL_STEPS])
            0: begin  // 8 bits
                result_out <= (mulProd[`MUL_STEPS-1] + mul_addend[`MUL_STEPS]) & 8'hFF;
                end
            1: begin  // 16 bit
                result_out <= (mulProd[`MUL_STEPS-1] + mul_addend[`MUL_STEPS]) & 16'hFFFF;
                end
            2: begin  // 32 bitss
                result_out <= (mulProd[`MUL_STEPS-1] + mul_addend[`MUL_STEPS]) & 32'hFFFFFFFF;
                end
            3: begin  // 64 bits
                result_out <= (mulProd[`MUL_STEPS-1] + mul_addend[`MUL_STEPS]);
                end
            endcase
        end
    end else if (div_finished & !(mulLine[`MUL_STEPS])) begin
        // output division result unless result bus is occupied by multiplication result
        case (div_optype[1:0])
        0: begin 
            // 8 bit
            result_out <= div_result[7:0];
            end
        1: begin 
            // 16 bit
            result_out <= div_result[15:0];
            end
        2: begin 
            // 32 bit
            result_out <= div_result[31:0];
            end
        3: begin 
            // 64 bits if supported
            result_out <= div_result;
            end
        endcase
        register_write_out <= 1;
        valid_out <= 1;
        register_a_out <= {1'b0,div_register};
        tag_val_out <= div_tag;
        div_out <= 1;
    
    end

    if (mulLine[`MUL_STEPS-1]) begin  // multiplication result has priority on result bus
        predict_tag2_out <= tag_val[`MUL_STEPS-1]; // forthcoming tag on result bus 2 for multiplication result
    end else if (end_div_next) begin
        predict_tag2_out <= div_tag;   
    end
     
    stall_out <= stall & valid & !reset;   
    stall_next_out <= (stall | stall_next) & !reset;   
    error_out <= error & valid & !reset;            // unknown instruction   
    error_parm_out <= error_parm & valid & !reset;  // wrong parameter   


    // outputs for debugger:
    debug1_out[7:0]  <= tag_val_in;
    debug1_out[15:8] <= div_tag;
    
    debug1_out[16]   <= div_finished;
    debug1_out[17]   <= end_div_next;
    debug1_out[18]   <= end_div;   
    debug1_out[19]   <= fasttrack;
    
    debug1_out[20]   <= start_div;
    debug1_out[21]   <= div_busy;
    debug1_out[22]   <= wait_result_bus;
    debug1_out[23]   <= wait_result_bus_next;
    
    debug1_out[24]   <= div_predict_in & (start_div | (div_busy & !end_div)); // stall_next 1
    debug1_out[25]   <= (opx >= `II_DIV & opx <= `II_REM_U) & valid_in & tag_val_in != div_tag & div_busy; // 2
    debug1_out[26]   <= (opx >= `II_DIV & opx <= `II_REM_U) & valid_in; // stall_next 3, not used 
    debug1_out[27]   <= slowtrack;
    
    debug1_out[28]   <= div_predict_in;
    debug1_out[29]   <= div_loop;
    debug1_out[30]   <= stall;
    debug1_out[31]   <= stall_next;  
    
    /*
    debug2_out[15:0]  <= div_A;    
    debug2_out[19:16] <= div_options;    
    debug2_out[20] <= signed_dision;
    debug2_out[21] <= signbit2;    
    debug2_out[22] <= div_rounding;
    debug2_out[23] <= div_negative;        
    debug2_out[30:24] <= last_tag;*/

    debug2_out[3:0]  <= tag_val[0];    
    debug2_out[7:4]  <= tag_val[1];    
    debug2_out[11:8]  <= tag_val[2];    
    debug2_out[15:12]  <= tag_val[3];  

    debug2_out[16]  <= start_mul;
    debug2_out[20]  <= stall;
    debug2_out[21]  <= stall_next;

    
    //debug2_out[31] <= &instruction_in & ot_in[2] & &option_bits_in & &mask_val_in; // avoid warning for unused inputs
end

endmodule
