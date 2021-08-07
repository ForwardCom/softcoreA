//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2021-06-06
// Last modified:  2021-06-06
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
    input clock,                            // system clock (100 MHz)
    input clock_enable,                     // clock enable. Used when single-stepping
    input reset,                            // system reset
    input valid_in,                         // data from previous stage ready
    input stall_in,                         // pipeline is stalled    
    input [31:0] instruction_in,            // current instruction, up to 3 words long. Only first word used here
    input [`TAG_WIDTH-1:0] tag_val_in,      // instruction tag value    
    input [1:0]  category_in,               // 00: multiformat, 01: single format, 10: jump
    input        mask_alternative_in,       // mask register and fallback register used for alternative purposes
    input [1:0]  result_type_in,            // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    input        vector_in,                 // vector registers used
    input [6:0]  opx_in,                    // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
    input [2:0]  ot_in,                     // operand type
    input [5:0]  option_bits_in,            // option bits from IM3 or mask
     
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
    input [`MASKSZ:0] regmask_val_in,       // mask register
    input [`RB1:0] ram_data_in,             // memory operand from data ram
    input        opr2_from_ram_in,          // value of operand 2 comes from data ram
    input        opr3_from_ram_in,          // value of last operand comes from data ram    
    input        opr1_used_in,              // operand1_in is needed
    input        opr2_used_in,              // operand2_in is needed
    input        opr3_used_in,              // operand3_in is needed
    input        regmask_used_in,           // regmask_val_in is needed

    output reg valid_out,                   // for debug display: alu is active
    output reg register_write_out, 
    output reg [4:0] register_a_out,        // register to write
    output reg [`RB1:0] result_out,         // 
    output reg [`TAG_WIDTH-1:0] tag_val_out,// instruction tag value
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
logic [`MASKSZ:0] regmask_val;              // mask register
logic [1:0]  otout;                         // operand type for output
logic [5:0]  msb;                           // index to most significant bit
logic signbit2, signbit3;                   // sign bits of three operands
logic [`RB1:0] sbit;                        // position of sign bit 
logic [`RB1:0] result;                      // result for output
logic [1:0]  result_type;                   // type of result
logic [6:0]  opx;                           // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
logic mask_off;                             // result is masked off
logic stall;                                // waiting for operands
logic stall_next;                           // will be waiting for operands in next clock cycle
logic error;                                // unknown instruction
logic error_parm;                           // wrong parameter for instruction

// It seems to be more efficient to truncate operands locally by ANDing with sizemask than to 
// make separate wires for the truncated operands, because wiring is more expensive than logic:
logic [`RB1:0] sizemask;                    // mask for operand type

logic [31:0] temp_debug;                    // temporary debug signals

always_comb begin
    // get all inputs
    stall = 0;
    stall_next = 0;    
    regmask_val = 0;
    temp_debug = 0;                         // temporary debug signals
    
    if (regmask_val_in[`MASKSZ]) begin      // value missing
        if (write_en1 && regmask_val_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            regmask_val = writeport1_in;    // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && regmask_val_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            regmask_val = writeport2_in[(`MASKSZ-1):0]; // obtained from result bus 2
        end else begin
            if (regmask_used_in) begin
                stall = 1;                  // operand not ready
                temp_debug[0] = 1;          // debug info about cause of stall
                if (regmask_val_in[`TAG_WIDTH-1:0] != predict_tag1_in && regmask_val_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                    stall_next = 1;         // operand not ready in next clock cycle
                end
            end                 
        end
    end else begin                          // value available
        regmask_val = regmask_val_in;
    end

    mask_off = regmask_used_in && regmask_val[`MASKSZ] == 0 && regmask_val[0] == 0 && !mask_alternative_in; 
    
    operand1 = 0;    
    if (operand1_in[`RB]) begin             // value missing
        if (write_en1 && operand1_in[`TAG_WIDTH-1:0] == write_tag1_in) begin
            operand1 = writeport1_in;       // obtained from result bus 1 (which may be my own output)
        end else if (write_en2 && operand1_in[`TAG_WIDTH-1:0] == write_tag2_in) begin
            operand1 = writeport2_in;       // obtained from result bus 2
        end else begin
            if (opr1_used_in) begin
                stall = 1;                  // operand not ready
                temp_debug[1] = 1;          // debug info about cause of stall
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
            if (opr2_used_in && !mask_off) begin
                stall = 1;                  // operand not ready
                temp_debug[2] = 1;          // debug info about cause of stall
                if (operand2_in[`TAG_WIDTH-1:0] != predict_tag1_in && operand2_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                    stall_next = 1;         // operand not ready in next clock cycle
                end                 
            end
        end 
    end else begin                          // value available
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
            if (opr3_used_in && !mask_off) begin
                stall = 1;                  // operand not ready
                temp_debug[3] = 1;          // debug info about cause of stall
                if (operand3_in[`TAG_WIDTH-1:0] != predict_tag1_in && operand3_in[`TAG_WIDTH-1:0] != predict_tag2_in) begin
                    stall_next = 1;         // operand not ready in next clock cycle
                end                 
            end
        end
    end else begin                          // value available
        operand3 = operand3_in[`RB1:0];
    end
     
    opx = opx_in;                           // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
    result = 0;
    otout = ot_in[1:0];                     // operand type for output
    result_type = result_type_in;
    error = 0;
    error_parm = 0;

    case (ot_in[1:0])
    0: begin 
        msb = 7;   // 8 bit
        sbit = 8'H80;
        sizemask = 8'HFF;
        //signbit1 = operand1[7];
        signbit2 = operand2[7];
        signbit3 = operand3[7];
        end
    1: begin
        msb = 15;   // 16 bit
        sbit     = 16'H8000;
        sizemask = 16'HFFFF;
        //signbit1 = operand1[15];
        signbit2 = operand2[15];
        signbit3 = operand3[15];
        end           
    2: begin
        msb = 31;   // 32 bit
        sbit     = 32'H80000000;
        sizemask = 32'HFFFFFFFF;
        //signbit1 = operand1[31];
        signbit2 = operand2[31];
        signbit3 = operand3[31];        
        end
    3: begin
        msb = `RB1;   // 64 bit
        sbit     = {1'b1,{(`RB-1){1'b0}}};
        sizemask = ~(`RB'b0);        
        //signbit1 = operand1[`RB1];
        signbit2 = operand2[`RB1];
        signbit3 = operand3[`RB1];
        end
    endcase
    
    
    ////////////////////////////////////////////////
    //             Select ALU operation
    ////////////////////////////////////////////////
    
    result = 0;
    
    if (opx == `II_MUL) begin
    
       error = 1;  // instruction not supported yet    

    end else if (opx == `II_MUL_HI || opx == `II_MUL_HI_U) begin

       error = 1;  // instruction not supported yet    

    end else if (opx == `II_DIV || opx == `II_DIV_U) begin

       error = 1;  // instruction not supported yet    

    end else if (opx == `II_REM || opx == `II_REM_U) begin

       error = 1;  // instruction not supported yet    

    end else begin
    
        error = 1;  // unknown instruction
        
    end
    
    if (vector_in) error = 1;  // Vector instructions not supported yet

end


// output
always_ff @(posedge clock) if (clock_enable) begin
    if (!valid_in) begin
        register_write_out <= 0;
        // note: the FPGA has no internal tri-state buffers. We need to simulate result bus by or'ing outputs 
        result_out <= 0;
        register_a_out <= 0;
        tag_val_out <= 0;

    // stall_in must disable the output to avoid executing the same instruction twice)
    end else if (stall || stall_in) begin
        register_write_out <= 0;
        result_out <= 0;
        register_a_out <= 0;
        tag_val_out <= 0;

    end else if (result_type != `RESULT_REG) begin
        // no output?
        register_write_out <= 0;
        result_out <= 0;
        register_a_out <= 0;
        tag_val_out <= 0;
        
    end else if (regmask_used_in && !regmask_val[0] & !vector_in) begin
        // mask is zero. output is fallback
        case (otout)
        0: result_out <= operand1[7:0];
        1: result_out <= operand1[15:0];
        2: result_out <= operand1[31:0];
        3: result_out <= operand1[`RB1:0];
        endcase
        register_write_out <= ~reset;
        register_a_out <= {1'b0,instruction_in[`RD]};
        tag_val_out <= tag_val_in;
        
    end else begin
        // normal register output
        case (otout)
        0: result_out <= result[7:0];
        1: result_out <= result[15:0];
        2: result_out <= result[31:0];
        3: result_out <= result[`RB1:0];
        endcase
        register_write_out <= ~reset;
        register_a_out <= {1'b0,instruction_in[`RD]};
        tag_val_out <= tag_val_in;
    end
    
    valid_out <= !stall & valid_in & !reset;
    stall_out <= stall  & valid_in & !reset;   
    stall_next_out <= stall_next & valid_in & !reset;   
    error_out <= error & valid_in & !reset;            // unknown instruction   
    error_parm_out <= error_parm & valid_in & !reset;  // wrong parameter   
    
    // outputs for debugger:
    debug1_out <= 0;
    
    debug1_out[6:0]   <= opx; 
    
    debug1_out[21:20] <= category_in;
    
    debug1_out[24]    <= stall;
    debug1_out[25]    <= stall_next;
    debug1_out[27]    <= error;
    

    debug2_out <= temp_debug;

    debug2_out[16] <= opr1_used_in;     
    debug2_out[17] <= opr2_used_in;     
    debug2_out[18] <= opr3_used_in;     
    debug2_out[19] <= regmask_used_in;     

    debug2_out[20] <= mask_alternative_in;     
    debug2_out[21] <= mask_off;
    debug2_out[22] <= regmask_val_in[0];
    debug2_out[23] <= regmask_val_in[`MASKSZ];     
    
    debug2_out[27:24] <= regmask_val[3:0];     
    debug2_out[28] <= regmask_val[`MASKSZ];     
    
end

endmodule
