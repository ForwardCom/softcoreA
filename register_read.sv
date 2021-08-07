//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date: 2020-06-01
// Last modified: 2021-02-16
// Module Name: Register read
// Project Name: ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions: Vivado v. 2019.2
// License: CERN-OHL-W
// Description: This pipeline stage comes after the decoder. 
// It contains the integer register file. Register read requests come from the 
// decoder stage and nowhere else. Register write commands come from the result buses.
// Tags are written to the register entries for values in flight in the pipeline.
//
// Putting the register file into this pipeline stage rather than in a separate module
// saves a lot of synchronization problems when results from a separate register file
// may come at a wrong clock cycle due to pipeline stall. 
// This does not make this module excessively big. 
//
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"


module register_read (
    input clock,                            // system clock (100 MHz)
    input clock_enable,                     // clock enable. Used when single-stepping
    input reset,                            // system reset. 
    input valid_in,                         // data from fetch module ready
    input stall_in,                         // a later stage in pipeline is stalled
    input [`CODE_ADDR_WIDTH-1:0] instruction_pointer_in, // address of current instruction
    input [95:0] instruction_in,            // current instruction, up to 3 words long
    input        tag_write_in,              // write tag
    input [`TAG_WIDTH-1:0] tag_val_in,      // instruction tag value    
    input        vector_in,                 // this is a vector instruction
    input [1:0]  category_in,               // 00: multiformat, 01: single format, 10: jump
    input [1:0]  format_in,                 // 00: format A, 01: format E, 10: format B, 11: format C (format D never goes through decoder)
    input [2:0]  rs_status_in,              // use of RS
    input [2:0]  rt_status_in,              // Use of RT
    input [1:0]  ru_status_in,              // Use of RU
    input [1:0]  rd_status_in,              // Use of RD as input
    input [1:0]  mask_status_in,            // Use of mask register    
    input        mask_options_in,           // mask register may contain options
    input        mask_alternative_in,       // mask register and fallback register used for alternative purposes
    input [2:0]  fallback_use_in,           // 0: no fallback, 1: same as first source operand, 2-4: RU, RS, RT    
    input [1:0]  num_operands_in,           // number of source operands
    input [1:0]  result_type_in,            // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    input [1:0]  offset_field_in,           // address offset. 0: none, 1: 8 bit, possibly scaled, 2: 16 bit, 3: 32 bit
    input [1:0]  immediate_field_in,        // immediate data field. 0: none, 1: 8 bit, 2: 16 bit, 3: 32 or 64 bit
    input [1:0]  scale_factor_in,           // 00: index is not scaled, 01: index is scaled by operand size, 10: index is scaled by -1
    input        index_limit_in,            // IM2 or IM3 contains a limit to the index
    
    // ports for register write
    input [`RB1:0] writeport1,              // write port 1
    input [5:0] writea1,                    // address input for writeport1 (extra bit is 1 for system registers)
    input write_en1,                        // write enable for writeport1
    input [`TAG_WIDTH-1:0] write_tag1,      // tag must match to enable writing
    input [`RB1:0] writeport2,
    input [4:0] writea2,
    input write_en2,
    input [`TAG_WIDTH-1:0] write_tag2,
    input [5:0] debug_reada,                // read port for debugger

    output reg        valid_out,            // An instruction is ready for output to next stage
    output reg [`CODE_ADDR_WIDTH-1:0] instruction_pointer_out, // address of current instruction
    output reg [95:0] instruction_out,      // first word of instruction    
    output reg        stall_predict_out,    // predict next stage will stall
    
    output reg [`TAG_WIDTH-1:0] tag_val_out,// instruction tag value
    output reg        vector_out,           // this is a vector instruction
    output reg [1:0]  category_out,         // 00: multiformat, 01: single format, 10: jump
    output reg [1:0]  format_out,           // 00: format A, 01: format E, 10: format B, 11: format C (format D never goes through decoder)
    output reg [1:0]  num_operands_out,     // number of source operands
    output reg [1:0]  result_type_out,      // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    output reg [1:0]  offset_field_out,     // address offset. 0: none, 1: 8 bit, possibly scaled, 2: 16 bit, 3: 32 bit
    output reg [1:0]  immediate_field_out,  // immediate data field. 0: none, 1: 8 bit, 2: 16 bit, 3: 32 or 64 bit
    output reg [1:0]  scale_factor_out,     // 00: index is not scaled, 01: index is scaled by operand size, 10: index is scaled by -1
    output reg        index_limit_out,      // IM2 or IM3 contains a limit to the index

    output reg [`RB:0] rd_val_out,          // value of register operand RD, bit `RB indicates missing 
    output reg [`RB:0] rs_val_out,          // value of register operand RS, bit `RB indicates missing 
    output reg [`RB:0] rt_val_out,          // value of register operand RT, bit `RB indicates missing 
    output reg [`RB:0] ru_val_out,          // value of register operand RU, bit `RB indicates missing 
    output reg [`MASKSZ:0]  regmask_val_out,// value of mask register, bit 32 indicates missing

    output reg [1:0]   rd_status_out,       // uas of RD as input
    output reg [2:0]   rs_status_out,       // use of RS
    output reg [2:0]   rt_status_out,       // use of RT 
    output reg [1:0]   ru_status_out,       // use of RU 
    output reg [1:0]   mask_status_out,     // 1: mask register is used    
    output reg         mask_alternative_out,// mask register and fallback register used for alternative purposes
    output reg [2:0]   fallback_use_out,    // 0: no fallback, 1: same as first source operand, 2-4: RU, RS, RT
    output reg [32:0]  debugport_out        // read for debugging purpose 
);

// components of instruction
logic [1:0]  il;                            // instruction length
logic [2:0]  ot;                            // operand type
logic [4:0]  mask;                          // mask register number
logic [4:0]  rd;                            // rd register number
logic [5:0]  rs;                            // rs register number
logic [5:0]  rt;                            // rt register number
logic [4:0]  ru;                            // ru register number
logic [5:0]  tag_a;                         // tag address

// register values. Extra bit is 1 if not found
logic [`RB:0] rd_val;                       // value of register RD 
logic [`RB:0] rs_val;                       // value of register RS 
logic [`RB:0] rt_val;                       // value of register RT
logic [`RB:0] ru_val;                       // value of register RU
logic [`MASKSZ:0]  mask_val;                // value of mask register
logic         mask_used;                    // a mask register is used
logic         mask_off;                     // mask is known to be 0. input operands are not used. fallback may be used
logic         stall_predict;                // predict that address generator will stall in next clock cycle
logic [`COMMON_ADDR_WIDTH:0] instr_end;     // address at end of instruction (word based)

logic [`TAG_WIDTH:0] rd_tag;                // tag to look for if rd not available
logic [`TAG_WIDTH:0] rs_tag;                // tag to look for if rs not available
logic [`TAG_WIDTH:0] rt_tag;                // tag to look for if rt not available
logic [`TAG_WIDTH:0] ru_tag;                // tag to look for if ru not available
logic [`TAG_WIDTH:0] mask_tag;              // tag to look for if mask not available

// temporary debug info
logic [31:0] debug_bits;
logic [31:0] debug_bits_tag;

// temporary storage of register values during stall. Extra bit is 1 if not found
reg [`RB:0] rd_val_temp;                    // temporary value of register RD
reg [`RB:0] rs_val_temp;                    // temporary value of register RS
reg [`RB:0] rt_val_temp;                    // temporary value of register RT
reg [`RB:0] ru_val_temp;                    // temporary value of register RU
reg [`MASKSZ:0] mask_val_temp;              // temporary value of mask mask register
reg         last_stall;                     // was stalled in last clock cycle. May obtain values from the temporary registers

always_comb begin
// extract instruction fields, etc
    il   = instruction_in[`IL];
    ot   = instruction_in[`OT];    
    mask = instruction_in[`MASK]; 
    rd   = instruction_in[`RD];
    rs   = {(rs_status_in == `REG_SYSTEM), instruction_in[`RS]};
    rt   = instruction_in[`RT];
    ru   = instruction_in[`RU];
    if (mask_status_in != `REG_UNUSED && instruction_in[`MASK] == 7) mask = `NUMCONTR;
    if (rs_status_in == `REG_POINTER && offset_field_in >= `OFFSET_2) begin
        if (instruction_in[`RS] == 28) rs = `THREADP;
        if (instruction_in[`RS] == 29) rs = `DATAP;    
    end
    /*
    if (rt_status_in == `REG_POINTER && offset_field_in >= `OFFSET_2) begin
        if (instruction_in[`RT] == 28) rt = `THREADP;
        if (instruction_in[`RT] == 29) rt = `DATAP;    
    end    */
    tag_a = {result_type_in == `RESULT_SYS, rd}; // tag address
    instr_end = instruction_pointer_in + (il[1] ? il : 2'b01) + {1'b1,{(`CODE_ADDR_START-2){1'b0}}}; // address at end of instruction
end

/************************************************************
         general purpose and system register file
*************************************************************
Values of read addresses:
0-30: register r0 - r30
31:   data stack pointer
32:   numeric control register
33:   thread pointer
34:   data section pointer
35:   currently unused 
************************************************************/

parameter num_reg = 32 + `NUM_SYS_REGISTERS;     // 32 general purpose registers and 3 system registers     
reg [`RB:0] registers [num_reg];

// writing to registers through write ports
// generation loop for all general purpose and system registers    
genvar i;                  
for (i=0; i < num_reg; i++) begin
    always_ff @(posedge clock) if (clock_enable) begin
        if (reset)
            registers[i] <= 0; // reset general purpose registers, but not system registers 
        else if (tag_write_in && valid_in && i == tag_a)  
            registers[i] <= {1'b1, {(`RB-`TAG_WIDTH){1'b0}}, tag_val_in};    
        else if (write_en1 && i == writea1 && write_tag1 == registers[i][`TAG_WIDTH-1:0]) 
            registers[i] <= {1'b0,writeport1};
        else if (write_en2 && i == writea2 && write_tag2 == registers[i][`TAG_WIDTH-1:0]) 
            registers[i] <= {1'b0,writeport2};
    end
end

// get general purpose and system register values
always_comb begin
    // tags to look for if registers are not available
    if (last_stall) begin
        // the tags to look for must be sampled in the first clock cycle of a stall 
        rd_tag   = {rd_val_temp[`RB],rd_val_temp[`TAG_WIDTH-1:0]};
        rs_tag   = {rs_val_temp[`RB],rs_val_temp[`TAG_WIDTH-1:0]};
        rt_tag   = {rt_val_temp[`RB],rt_val_temp[`TAG_WIDTH-1:0]};
        ru_tag   = {ru_val_temp[`RB],ru_val_temp[`TAG_WIDTH-1:0]};
        mask_tag = {mask_val_temp[`MASKSZ],mask_val_temp[`TAG_WIDTH-1:0]};
    end else begin
        // the tags to look for are found in the register file  
        rd_tag   = {registers[rd][`RB],registers[rd][`TAG_WIDTH-1:0]};
        rs_tag   = {registers[rs][`RB],registers[rs][`TAG_WIDTH-1:0]};
        rt_tag   = {registers[rt][`RB],registers[rt][`TAG_WIDTH-1:0]};
        ru_tag   = {registers[ru][`RB],registers[ru][`TAG_WIDTH-1:0]};
        mask_tag = {registers[mask][`RB],registers[mask][`TAG_WIDTH-1:0]};
    end

    if (rd_status_in == `REG_UNUSED) begin
        rd_val = 0;
    end else if (write_en1 && rd == writea1 && rd_tag[`TAG_WIDTH] && write_tag1 == rd_tag[`TAG_WIDTH-1:0]) begin
        rd_val = {1'b0,writeport1};         // forwarding from write port 1
    end else if (write_en2 && rd == writea2 && rd_tag[`TAG_WIDTH] && write_tag2 == rd_tag[`TAG_WIDTH-1:0]) begin
        rd_val = {1'b0,writeport2};         // forwarding from write port 2
    end else if (last_stall) begin
        rd_val = rd_val_temp;
    end else begin 
        rd_val = registers[rd];             // read value or tag from register file   
    end    

    if (rs_status_in == `REG_UNUSED) begin
        rs_val = 0;        
    end else if (rs_status_in == `REG_POINTER && offset_field_in >= `OFFSET_2 && instruction_in[`RS] == 30) begin
        rs_val = {instr_end,2'b0};             // instruction pointer as base pointer
    end else if (write_en1 && rs == writea1 && rs_tag[`TAG_WIDTH] && write_tag1 == rs_tag[`TAG_WIDTH-1:0]) begin
        rs_val = {1'b0,writeport1};         // forwarding from write port 1
    end else if (write_en2 && rs == writea2 && rs_tag[`TAG_WIDTH] && write_tag2 == rs_tag[`TAG_WIDTH-1:0]) begin
        rs_val = {1'b0,writeport2};         // forwarding from write port 2
    end else if (last_stall) begin
        rs_val = rs_val_temp;
    end else begin 
        rs_val = registers[rs];             // read value or tag from register file   
    end    
      
    if (rt_status_in == `REG_UNUSED) begin
        rt_val = 0;
    //end else if (rt_status_in == `REG_POINTER && offset_field_in >= `OFFSET_2 && instruction_in[`RT] == 30) begin
    //    rt_val = {instr_end,2'b0} ; // instruction pointer as base pointer
    end else if (write_en1 && rt == writea1 && rt_tag[`TAG_WIDTH] && write_tag1 == rt_tag[`TAG_WIDTH-1:0]) begin
        rt_val = {1'b0,writeport1};         // forwarding from write port 1
    end else if (write_en2 && rt == writea2 && rt_tag[`TAG_WIDTH] && write_tag2 == rt_tag[`TAG_WIDTH-1:0]) begin
        rt_val = {1'b0,writeport2};         // forwarding from write port 2
    end else if (last_stall) begin
        rt_val = rt_val_temp;
    end else begin 
        rt_val = registers[rt];             // read value or tag from register file   
    end    
        
    if (ru_status_in == `REG_UNUSED) begin
        ru_val = 0;
    end else if (write_en1 && ru == writea1 && ru_tag[`TAG_WIDTH] && write_tag1 == ru_tag[`TAG_WIDTH-1:0]) begin
        ru_val = {1'b0,writeport1};         // forwarding from write port 1
    end else if (write_en2 && ru == writea2 && ru_tag[`TAG_WIDTH] && write_tag2 == ru_tag[`TAG_WIDTH-1:0]) begin
        ru_val = {1'b0,writeport2};         // forwarding from write port 2        
    end else if (last_stall) begin
        ru_val = ru_val_temp;
    end else begin 
        ru_val = registers[ru];             // read value or tag from register file   
    end    

    if (mask_status_in == `REG_UNUSED) begin
        mask_val = 1;
    end else if (write_en1 && mask == writea1 && mask_tag[`TAG_WIDTH] && write_tag1 == mask_tag[`TAG_WIDTH-1:0]) begin
        mask_val = {1'b0,writeport1[`MASKSZ-1:0]};    // forwarding from write port 1
    end else if (write_en2 && mask == writea2 && mask_tag[`TAG_WIDTH] && write_tag2 == mask_tag[`TAG_WIDTH-1:0]) begin
        mask_val = {1'b0,writeport2[`MASKSZ-1:0]};    // forwarding from write port 2
    end else if (last_stall) begin
        mask_val = mask_val_temp;
    end else begin 
        mask_val = {registers[mask][`RB],registers[mask][`MASKSZ-1:0]}; // read value or tag from register file   
    end    
end

// save values during stall
always_ff @(posedge clock) if (clock_enable && valid_in) begin
    last_stall <= stall_in;
    if (stall_in) begin
        rd_val_temp <= rd_val;
        rs_val_temp <= rs_val;
        rt_val_temp <= rt_val;
        ru_val_temp <= ru_val;
        mask_val_temp <= mask_val;
    end else begin
        rd_val_temp <= {1'b1,`RB'b0};
        rs_val_temp <= {1'b1,`RB'b0};
        rt_val_temp <= {1'b1,`RB'b0};
        ru_val_temp <= {1'b1,`RB'b0};
        mask_val_temp <= {1'b1,`MASKSZ'b0};    
    end
end


always_comb begin
    // (The mask must be ignored for the NOP instruction. If there are any other instructions with 
    // zero operands that can have a valid mask then the above line must be modified.)
    mask_used = (format_in == `FORMAT_A || format_in == `FORMAT_E) && mask != 7 && num_operands_in != 0;
    // Check if result is masked off so that we don't have to wait for operands
    mask_off = mask_used && mask_val[`MASKSZ] == 0 && mask_val[0] == 0 && !mask_alternative_in && !vector_in; 
    
    stall_predict = 0;
    // rs used as pointer or index or vector length and not available in next clock cycle:
    if (rs_status_in >= `REG_POINTER && rs_val[`RB] && !mask_off) stall_predict = 1;
    // rt used as pointer and not available in next clock cycle:
    if (rt_status_in >= `REG_POINTER && rt_val[`RB] && !mask_off) stall_predict = 1;
    // rd is written to memory and not available in next clock cycle: 
    if (rd_status_in != 0 && result_type_in == `RESULT_MEM && rd_val[`RB] && !mask_off) stall_predict = 1;
    // mask value is needed for memory write
    if (mask_used && result_type_in == `RESULT_MEM && mask_val[`MASKSZ]) stall_predict = 1;

    // signals for debugging    
    debug_bits = 0;
    debug_bits[0]  = rs_status_in >= `REG_POINTER;
    
    debug_bits[8]  = rt_status_in >= `REG_POINTER;
    
    debug_bits[16] = rd_status_in;
    
    debug_bits[24] = stall_predict;
    debug_bits[25] = last_stall;
    debug_bits[26] = stall_in;
    debug_bits[27] = valid_in;
    
    debug_bits_tag = 0;
    //debug_bits_tag[`TAG_WIDTH-1:0] = tag_mirror[reg1_in];

end 

// get values of missing operands from result buses.
// if stalling: keep looking for results and keep the values until not stalled
always_ff @(posedge clock) if (clock_enable) begin

    // Predict stall in next stage if RS, RT, or RD is needed in the address generator stage 
    // and not yet available and not predicted to become available in the next clock cycle.
    // Note, that while the stall prediction is looking forward one stage in the pipeline, 
    // it should not apply if the instruction is not moving to the next stage yet, hence
    // stall_predict_out is not applied if stall_in.
    stall_predict_out <= stall_predict && !stall_in && !reset && valid_in;
    
    if (reset) valid_out <= 0;
    else if (!stall_in) valid_out <= valid_in;    
end

// generate outputs
always_ff @(posedge clock) if (clock_enable && !stall_in) begin
    // first two words of instruction
    instruction_out <= instruction_in;

    // register values out
    rd_val_out <= rd_val;                   // value of register operand RD, bit `RB indicates missing
    rs_val_out <= rs_val;                   // value of register operand RS, bit `RB indicates missing
    rt_val_out <= rt_val;                   // value of register operand RT, bit `RB indicates missing
    ru_val_out <= ru_val;                   // value of register operand RU, bit `RB indicates missing
    regmask_val_out <= mask_val;            // value of mask register, bit 32 indicates missing

    // other outputs are unchanged from input
    instruction_pointer_out <= instruction_pointer_in;
    tag_val_out <= tag_val_in;              // tag for current instruction
    vector_out <= vector_in;                // vector instruction
    category_out <= category_in;            // instruction category
    format_out <= format_in;                // instruction format
    rs_status_out <= rs_status_in;          // use of rs register
    rt_status_out <= rt_status_in;          // use of rt register
    ru_status_out <= ru_status_in;          // use of ru register
    rd_status_out <= rd_status_in;          // use of rd register
    mask_status_out <=  mask_used | mask_options_in; // use of mask register
    mask_alternative_out <= mask_alternative_in; // mask register and fallback register used for alternative purposes
    fallback_use_out <= fallback_use_in;    // 0: no fallback, 1: same as first source operand, 2-4: RU, RS, RT
    num_operands_out <= num_operands_in;    // number of input operands
    result_type_out <= result_type_in;      // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
    offset_field_out <= offset_field_in;    // address offset. 0: none, 1: 8 bit, possibly scaled, 2: 16 bit, 3: 32 bit
    immediate_field_out <= immediate_field_in; // immediate data field. 0: none, 1: 8 bit, 2: 16 bit, 3: 32 or 64 bit
    scale_factor_out <= scale_factor_in;    // 00: index is not scaled, 01: index is scaled by operand size, 10: index is scaled by -1
    index_limit_out <= index_limit_in;      // The field indicated by offset_field contains a limit to the index    
end

always_ff @(posedge clock) begin
    debugport_out <= registers[debug_reada];// read register by debugger
end

endmodule
