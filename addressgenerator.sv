//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2020-06-04
// Last modified:  2022-12-25
// Module Name:    decoder
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Address generator. Calculates address of memory operand, sorts other operands
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"


module addressgenerator(
    input clock,                            // system clock
    input clock_enable,                     // clock enable. Used when single-stepping
    input reset,                            // system reset. 
    input valid_in,                         // data from fetch module ready
    input stall_in,                         // a later stage in pipeline is stalled
    input [`CODE_ADDR_WIDTH-1:0] instruction_pointer_in, // address of current instruction
    input [95:0] instruction_in,            // current instruction, up to 3 words long
    input [`TAG_WIDTH-1:0] tag_val_in,      // instruction tag value    
    input        vector_in,                 // this is a vector instruction
    input [1:0]  category_in,               // 00: multiformat, 01: single format, 10: jump
    input [1:0]  format_in,                 // 00: format A, 01: format E, 10: format B, 11: format C
    input [2:0]  rs_status_in,              // 1: RS is register operand, 2: RS is pointer, 3: RS is index,
                                            // 4: RS is vector length
    input [2:0]  rt_status_in,              // 1: RT is register operand, 2: RT is pointer
    input [1:0]  ru_status_in,              // 1: RU is used as register operand
    input [1:0]  rd_status_in,              // 1: RD is used as input
    input [1:0]  mask_status_in,            // 1: mask register used
    input        mask_alternative_in,       // mask register and fallback register used for alternative purposes
    input [2:0]  fallback_use_in,           // 0: none, 1: same as first source operand, 2-4: RU, RS, RT        
    input [1:0]  num_operands_in,           // number of source operands
    input [1:0]  result_type_in,            // result: 0: register, 1: system reg, 2: memory, 3: other or nothing
    input [1:0]  offset_field_in,           // address offset. 0: none, 1: 8 bit, possibly scaled, 
                                            // 2: 16 bit, 3: 32 bit
    input [1:0]  immediate_field_in,        // immediate data field. 0: none, 1: 8 bit, 2: 16 bit, 3: 32 or 64 bit
    input [1:0]  scale_factor_in,           // 00: index is not scaled, 01: index is scaled by operand size,
                                            // 10: index is scaled by -1
    input        index_limit_in,            // IM4 or IM7 contains a limit to the index
    
    // register values 
    input [`RB:0] rd_val_in,                // value of register operand RD, bit `RB indicates missing 
    input [`RB:0] rs_val_in,                // value of register operand RS, bit `RB indicates missing 
    input [`RB:0] rt_val_in,                // value of register operand RT, bit `RB indicates missing 
    input [`RB:0] ru_val_in,                // value of register operand RU, bit `RB indicates missing 
    input [`MASKSZ:0]  mask_val_in,         // value of mask register, bit `MASKSZ indicates missing

    // monitor result buses:
    input write_en1,                        // a result is written to writeport1
    input [`TAG_WIDTH-1:0] write_tag1_in,   // tag of result inwriteport1
    input [`RB1:0] writeport1_in,           // result bus 1
    input write_en2,                        // a result is written to writeport2
    input [`TAG_WIDTH-1:0] write_tag2_in,   // tag of result inwriteport2
    input [`RB1:0] writeport2_in,           // result bus 2    
    input [`TAG_WIDTH-1:0] predict_tag1_in, // tag on result bus 1 in next clock cycle
    input [`TAG_WIDTH-1:0] predict_tag2_in, // tag on result bus 2 in next clock cycle    

    // calculated read and write memory addresses go to data cache
    output reg [`COMMON_ADDR_WIDTH-1:0] read_write_address_out, // address of memory operand
    output reg        read_enable_out,      // read from data cache
    output reg [1:0]  read_data_size_out,   // 8, 16, 32, or 64 bits read    
    output reg [7:0]  write_enable_out,     // write enable for each byte separately 
    output reg [63:0] write_data_out,       // data to write

    // instruction output to next pipeline stage    
    output reg        valid_out,            // An instruction is ready for output to next stage
    output reg [`CODE_ADDR_WIDTH-1:0] instruction_pointer_out, // address of current instruction
    output reg [63:0] instruction_out,      // first word of instruction    
    output reg        stall_predict_out,    // will be waiting for an operand    
    output reg        div_predict_out,      // a division instruction is underway
    output reg [`TAG_WIDTH-1:0] tag_val_out,// instruction tag value

    output reg [`RB:0] operand1_out,        // value of first operand, bit `RB indicates invalid 
    output reg [`RB:0] operand2_out,        // value of second operand, bit `RB indicates invalid 
    output reg [`RB:0] operand3_out,        // value of last, bit `RB indicates valid 
    output reg [`MASKSZ:0] mask_val_out,    // value of mask register, high bit indicates valid

    output reg        vector_out,           // this is a vector instruction
    output reg [1:0]  category_out,         // 00: multiformat, 01: single format, 10: jump
    output reg [1:0]  format_out,           // 00: format A, 01: format E, 10: format B, 11: format C
    output reg        mask_status_out,      // 1: mask register used
    output reg        mask_alternative_out, // mask register and fallback register used for alternative purposes
    output reg [2:0]  fallback_use_out,     // 0: no fallback, 1: same as first source operand, 2-4: RU, RS, RT
    output reg [1:0]  num_operands_out,     // number of source operands    
    output reg [1:0]  result_type_out,      // result: 0: register, 1: system reg, 2: memory, 3: other or nothing
    output reg [1:0]  offset_field_out,     // address offset. 0: none, 1: 8 bit, possibly scaled, 
                                            // 2: 16 bit, 3: 32 bit
    output reg [1:0]  immediate_field_out,  // immediate data field. 0: none, 1: 8 bit, 2: 16 bit, 3: 32 or 64 bit
    output reg [1:0]  scale_factor_out,     // 00: index is not scaled, 01: index is scaled by operand size,
                                            // 10: index is scaled by -1
    output reg        memory_operand_out,   // the instruction has a memory operand
    output reg        array_error_out,      // array index exceeds limit
    output reg        options5_out,         // IM5 containts option bits
    output reg [31:0] debug1_out,           // temporary output for debugging purpose
    output reg [31:0] debug2_out,           // temporary output for debugging purpose
    output reg [31:0] debug3_out            // temporary output for debugging purpose
);

// instruction components
logic [1:0]  il;                            // instruction length
logic [2:0]  mode;                          // instruction mode
logic        M;                             // M bit
logic [5:0]  op1;                           // OP1 in instruction
logic [1:0]  op2;                           // OP2 in instruction
logic [2:0]  otype;                         // operand type
logic [2:0]  mode2;                         // mode2 in format E
logic        option_bits_im5;               // IM5 is used for option bits

// synchronization signals
logic waiting;                              // waiting for needed register value
logic wait_next1;                           // predict that waiting for reg1 in the next clock cycle
logic wait_next2;                           // predict that waiting for reg2 in the next clock cycle
logic wait_next3;                           // predict that waiting for reg3 in the next clock cycle
logic wait_next4;                           // predict that waiting for mask in the next clock cycle
logic wait_next1234;                        // predict that waiting for one of these registers
logic div_in;                               // input instruction is division
logic address_instruction;                  // this is an address instruction. no memory access
logic mask_off;                             // result is masked off
logic new_instruction;                      // instruction is different from last instruction
logic array_error;                          // Array index exceeds limit
reg   last_stall;                           // was stalled in last clock cycle
reg   [`TAG_WIDTH-1:0] last_tag_val;        // check if instruction tag has changed

// components of address calculation
logic [`COMMON_ADDR_WIDTH-1:0] base_pointer;
logic [`COMMON_ADDR_WIDTH-1:0] address_index;
logic [`COMMON_ADDR_WIDTH-1:0] address_offset; // offset of memory operand
logic [`COMMON_ADDR_WIDTH-1:0] address;     // address of memory operand
logic [`RB1:0] write_data;                  // data to write

// register values. Extra bit is 1 if not found
logic [`RB:0] rs_val;                       // value of first register operand RS, bit `RB indicates missing 
logic [`RB:0] rt_val;                       // value of second register operand RT, bit `RB indicates missing 
logic [`RB:0] ru_val;                       // value of third register operand RD or RU, bit `RB indicates missing 
logic [`RB:0] rd_val;                       // value of third register operand RD or RU, bit `RB indicates missing 
logic [`MASKSZ:0] rm_val;                   // value of mask register, bit 32 indicates missing

logic rs_status;                            // value of rs is not known yet
logic rt_status;                            // value of rt is not known yet
logic ru_status;                            // value of ru is not known yet
logic rd_status;                            // value of rd is not known yet
logic rm_status;                            // value of mask is not known yet

logic [`TAG_WIDTH-1:0] rs_tag;              // tag if rs not known yet
logic [`TAG_WIDTH-1:0] rt_tag;              // tag if rs not known yet
logic [`TAG_WIDTH-1:0] ru_tag;              // tag if rs not known yet
logic [`TAG_WIDTH-1:0] rd_tag;              // tag if rs not known yet
logic [`TAG_WIDTH-1:0] rm_tag;              // tag if rs not known yet

// temporary storage of register values if found during stall. High bit is zero if valid
reg [`RB:0] rs_val_temp;                    // value of first register operand RS, bit `RB indicates missing 
reg [`RB:0] rt_val_temp;                    // value of second register operand RT, bit `RB indicates missing 
reg [`RB:0] ru_val_temp;                    // value of third register operand RD or RU, bit `RB indicates missing 
reg [`RB:0] rd_val_temp;                    // value of third register operand RD or RU, bit `RB indicates missing 
reg [`MASKSZ:0] rm_val_temp;                // value of mask register, bit 32 indicates missing


always_comb begin
    // components of format template
    il    = instruction_in[`IL];            // instruction length
    mode  = instruction_in[`MODE];          // format mode
    M     = instruction_in[`M];             // extension to operand type or mode
    op1   = instruction_in[`OP1];           // operation code
    op2   = instruction_in[`OP2];           // operation code extension
    otype = instruction_in[`OT] & {vector_in,2'b11}; // operand type
    mode2 = instruction_in[`MODE2];         // format mode extension
    
    // look for address instruction    
    if (il == 2 && mode == 1 && M && op1 == `II_ADDRESS_29) address_instruction = 1;
    else address_instruction = 0;
    
    // detect use of IM5 as option bits or extra operand
    option_bits_im5 = 0;
    if (il == 2 && (mode == 0 || mode == 5) && mode2 == 5) begin
        option_bits_im5 = 0;                // format 2.0.5 and 2.2.5 are using IM5 for an operand, not for options
    end else if (category_in == `CAT_MULTI) begin
        if (op1 == `II_SIGN_EXTEND_ADD || op1 == `II_COMPARE || op1 == `II_COMPARE_FLOAT16
         || op1 == `II_DIV || op1 == `II_DIV_REV || op1 == `II_DIV_U || op1 == `II_DIV_REV_U
         || op1 == `II_MIN || op1 == `II_MAX
         || op1 == `II_TEST_BIT || op1 == `II_TEST_BITS_AND || op1 == `II_TEST_BITS_OR
         || op1 == `II_MUL_ADD || op1 == `II_MUL_ADD2
         || op1 == `II_ADD_ADD) begin
            option_bits_im5 = 1;
        end
    end else if (il == 2) begin
        if (((mode == 0 && !M) || mode == 2) && mode2 == 7 && op1 == `II_MOVE_BITS && op2 == `II2_MOVE_BITS)
            option_bits_im5 = 1;
        if (mode == 2 && mode2 == 7 && op1 == `II_MASK_LENGTH && op2 == `II2_MASK_LENGTH)
            option_bits_im5 = 1;         
        if (((mode == 0 && !M) || mode == 2) && mode2 == 6 && op1 == `II_TRUTH_TAB3 && op2 == `II2_TRUTH_TAB3)
            option_bits_im5 = 1;
    end
    
    // check if current instruction is different from last clock cycle to prevent spill-over of temp register values
    new_instruction = (tag_val_in != last_tag_val) & valid_in;
    
    // status bits are 1 if register value not known yet
    rs_status = (last_stall & !new_instruction) ? rs_val_temp[`RB] : rs_val_in[`RB];
    rt_status = (last_stall & !new_instruction) ? rt_val_temp[`RB] : rt_val_in[`RB];
    ru_status = (last_stall & !new_instruction) ? ru_val_temp[`RB] : ru_val_in[`RB];
    rd_status = (last_stall & !new_instruction) ? rd_val_temp[`RB] : rd_val_in[`RB];
    rm_status = (last_stall & !new_instruction) ? rm_val_temp[`MASKSZ] : mask_val_in[`MASKSZ];

    rs_tag = rs_val_in[`TAG_WIDTH-1:0];
    rt_tag = rt_val_in[`TAG_WIDTH-1:0];
    ru_tag = ru_val_in[`TAG_WIDTH-1:0];
    rd_tag = rd_val_in[`TAG_WIDTH-1:0];
    rm_tag = mask_val_in[`TAG_WIDTH-1:0];
    
    // look at result buses for any missing register values:    
    if      (rs_status & write_en1 && rs_tag == write_tag1_in) rs_val = {1'b0, writeport1_in}; // from result bus 1
    else if (rs_status & write_en2 && rs_tag == write_tag2_in) rs_val = {1'b0, writeport2_in}; // from result bus 2
    else if (last_stall & !new_instruction) rs_val = rs_val_temp;
    else rs_val = rs_val_in;
    
    if      (rt_status & write_en1 && rt_tag == write_tag1_in) rt_val = {1'b0, writeport1_in}; // from result bus 1
    else if (rt_status & write_en2 && rt_tag == write_tag2_in) rt_val = {1'b0, writeport2_in}; // from result bus 2
    else if (last_stall & !new_instruction) rt_val = rt_val_temp;
    else rt_val = rt_val_in;

    if      (ru_status & write_en1 && ru_tag == write_tag1_in) ru_val = {1'b0, writeport1_in}; // from result bus 1
    else if (ru_status & write_en2 && ru_tag == write_tag2_in) ru_val = {1'b0, writeport2_in}; // from result bus 2
    else if (last_stall & !new_instruction) ru_val = ru_val_temp;
    else ru_val = ru_val_in;

    if      (rd_status & write_en1 && rd_tag == write_tag1_in) rd_val = {1'b0, writeport1_in}; // from result bus 1
    else if (rd_status & write_en2 && rd_tag == write_tag2_in) rd_val = {1'b0, writeport2_in}; // from result bus 2
    else if (last_stall & !new_instruction) rd_val = rd_val_temp;
    else rd_val = rd_val_in;

    if      (rm_status & write_en1 && rm_tag == write_tag1_in) rm_val = {1'b0, writeport1_in[`MASKSZ-1:0]}; // bus 1
    else if (rm_status & write_en2 && rm_tag == write_tag2_in) rm_val = {1'b0, writeport2_in[`MASKSZ-1:0]}; // bus 2
    else if (last_stall & !new_instruction) rm_val = rm_val_temp;
    else rm_val = mask_val_in;
    
end

// save values from result bus during stall
always_ff @(posedge clock) if (clock_enable) begin
    if ((stall_in | waiting) & valid_in) begin
        rs_val_temp <= rs_val;              // temporary save during stall
        rt_val_temp <= rt_val;              // temporary save during stall
        ru_val_temp <= ru_val;              // temporary save during stall
        rd_val_temp <= rd_val;              // temporary save during stall
        rm_val_temp <= rm_val;              // temporary save during stall
    end else begin
        rs_val_temp <= {1'b1,`RB'b0};       // reset when not stalled
        rt_val_temp <= {1'b1,`RB'b0};       // reset when not stalled
        ru_val_temp <= {1'b1,`RB'b0};       // reset when not stalled
        rd_val_temp <= {1'b1,`RB'b0};       // reset when not stalled
        rm_val_temp <= {1'b1,`MASKSZ'b0};   // reset when not stalled    
    end
end
   
    
always_comb begin
    // Check if result is masked off so that we don't have to wait for operands
    mask_off = mask_status_in != `REG_UNUSED & !mask_alternative_in & !vector_in & rm_val[`MASKSZ] == 0 & rm_val[0] == 0; 
    waiting = 0;
    wait_next1 = 0; wait_next2 = 0; wait_next3 = 0; wait_next4 = 0; 
    array_error = 0;
    div_in = category_in == `CAT_MULTI && op1 >= `II_DIV && op1 <= `II_REM_U;

    // check if we need to wait for register values
    if (rs_val[`RB] && rs_status_in == `REG_POINTER && !mask_off) begin
        waiting = 1; // value of RS needed in this stage for address calculation. must stall
        // predict if value will arrive in next clock cycle
        wait_next1 = predict_tag1_in != rs_val[`TAG_WIDTH-1:0] && predict_tag2_in != rs_val[`TAG_WIDTH-1:0]; 
    end
    
    if (rt_val[`RB] && rt_status_in >= `REG_INDEX && !mask_off) begin
        waiting = 1; // value of RT needed in this stage for address calculation. must stall
        // predict if value will arrive in next clock cycle
        wait_next2 = predict_tag1_in != rt_val[`TAG_WIDTH-1:0] && predict_tag2_in != rt_val[`TAG_WIDTH-1:0]; 
    end
    
    if (rd_val[`RB] && rd_status_in != 0 && result_type_in == `RESULT_MEM && !mask_off) begin
        waiting = 1; // value of RD needed in this stage for writing. must stall
        // predict if value will arrive in next clock cycle
        wait_next3 = predict_tag1_in != rd_val[`TAG_WIDTH-1:0] && predict_tag2_in != rd_val[`TAG_WIDTH-1:0]; 
    end
    
    if (rm_val[`MASKSZ] && mask_status_in != `REG_UNUSED && result_type_in == `RESULT_MEM) begin
        waiting = 1; // value of mask needed before write
        // predict if value will arrive in next clock cycle
        wait_next4 = predict_tag1_in != rm_val[`TAG_WIDTH-1:0] && predict_tag2_in != rm_val[`TAG_WIDTH-1:0]; 
    end 

    wait_next1234 = wait_next1 | wait_next2 | wait_next3 | wait_next4;    
    

    ////////////////////////////////////////////////
    //         calculate memory address:          //
    ////////////////////////////////////////////////
    
    // rs is base pointer
    base_pointer = rs_val[`RB1:0];    
    
    if (rt_status_in == `REG_INDEX) begin
        // rt is scaled index
        if (scale_factor_in == `SCALE_OS) begin
            case (otype) // operand type
            `OT_INT8:                 address_index =  rt_val[`RB-1:0];       // scale factor 1
            `OT_INT16:                address_index = {rt_val[`RB-2:0],1'b0}; // scale factor 2
            `OT_INT32, `OT_FLOAT32:   address_index = {rt_val[`RB-3:0],2'b0}; // scale factor 4
            `OT_INT64, `OT_FLOAT64:   address_index = {rt_val[`RB-4:0],3'b0}; // scale factor 8
            `OT_INT128,`OT_FLOAT128:  address_index = {rt_val[`RB-5:0],4'b0}; // scale factor 16         
            endcase
        end else if (scale_factor_in == `SCALE_MINUS) begin
            address_index = -rt_val[`RB1:0];          // scale factor -1
        end else begin
            address_index =  rt_val[`RB1:0];          // no scale factor
        end
        if (index_limit_in) begin
            // check index limit
            if (il == 3 && rt_val[`RB1:0] > instruction_in[95:64] 
            ||  il == 2 && rt_val[`RB1:0] > instruction_in[`IM4]) array_error = 1;
        end        
        
    end else begin
        address_index = 0;                            // no index
    end

    if (offset_field_in == `OFFSET_NONE) begin        // no offset
        address_offset = 0;
    end else if (offset_field_in == `OFFSET_1) begin  // 8 bit offset in IM1, scaled by operand size
        case (otype) // operand type
        `OT_INT8:                 address_offset = {{56{instruction_in[7]}},instruction_in[`IM1]};      // sign extend IM1
        `OT_INT16:                address_offset = {{55{instruction_in[7]}},instruction_in[`IM1],1'b0}; // sign extend, scale by 2
        `OT_INT32, `OT_FLOAT32:   address_offset = {{54{instruction_in[7]}},instruction_in[`IM1],2'b0}; // sign extend, scale by 4
        `OT_INT64, `OT_FLOAT64:   address_offset = {{53{instruction_in[7]}},instruction_in[`IM1],3'b0}; // sign extend, scale by 8
        `OT_INT128,`OT_FLOAT128:  address_offset = {{52{instruction_in[7]}},instruction_in[`IM1],4'b0}; // sign extend, scale by 16          
        endcase
    end else if(offset_field_in == `OFFSET_2) begin                        // 16 bit offset in IM4, not scaled    
        address_offset = {{48{instruction_in[47]}},instruction_in[`IM4]};  // sign extend IM4; 
    end else if (il == 2) begin                                            // 32 bit offset in IM6
        address_offset = {{32{instruction_in[63]}},instruction_in[63:32]}; // sign extend IM6;
    end else if (mode == 1 && op1 == 0) begin                              // format 3.1.0. Jump with memory offest in IM7
        address_offset = {{32{instruction_in[95]}},instruction_in[95:64]}; // sign extend IM6;
    end else begin                                                         // format 3.x.x, except 3.1.0
        address_offset = {{32{instruction_in[95]}},instruction_in[95:64]}; // sign extend IM7;
    end
    
    // calculated address
    address = base_pointer + address_index + address_offset;
    
    // data to write. (mask is handled below)
    if (category_in == `CAT_MULTI) begin
        write_data = rd_val;                    // write register
    end else begin
        write_data = instruction_in[63:32];     // write constant
    end
end

        
always_ff @(posedge clock) if (clock_enable) begin

    if (reset) begin
        valid_out  <= 0;
        last_stall <= 0;
        last_tag_val <= 0;
    end     
    
    // detect if valid instruction is stalled in output buffer    
    last_stall <= stall_in | waiting;
    
    // predict stalling in next clock cycle
    stall_predict_out <= wait_next1234 & valid_in;
    last_tag_val <= tag_val_in;
    
    // tell muldiv unit that a new division is underway
    div_predict_out <= div_in & valid_in & !wait_next1234 & !reset;
    //div_predict_out <= div_in & valid_in & !reset;

    if (!stall_in) begin
    
        // **** update output buffers: ****
        
        valid_out <= valid_in & !waiting & (tag_val_out != tag_val_in | last_stall);
        
        read_enable_out <= 0;
        write_enable_out <= 0;
    
        // output memory address for data cache read and write
        // must have natural alignment
        read_write_address_out <= address;
    
        if (result_type_in == `RESULT_MEM & !mask_off & !array_error & valid_in & !waiting
        & (tag_val_out != tag_val_in | last_stall)) begin
    
            // memory write
            if (otype == `OT_INT8) begin // write 8 bits
                case (address[2:0])
                0: begin
                    write_data_out <= write_data;
                    write_enable_out <= 8'b00000001; end 
                1: begin
                    write_data_out <= {write_data[7:0],8'b0};
                    write_enable_out <= 8'b00000010; end 
                2: begin
                    write_data_out <= {write_data[7:0],16'b0};
                    write_enable_out <= 8'b00000100; end 
                3: begin
                    write_data_out <= {write_data[7:0],24'b0};
                    write_enable_out <= 8'b00001000; end 
                4: begin
                    write_data_out <= {write_data[7:0],32'b0};
                    write_enable_out <= 8'b00010000; end 
                5: begin
                    write_data_out <= {write_data[7:0],40'b0};
                    write_enable_out <= 8'b00100000; end 
                6: begin
                    write_data_out <= {write_data[7:0],48'b0};
                    write_enable_out <= 8'b01000000; end 
                7: begin
                    write_data_out <= {write_data[7:0],56'b0};
                    write_enable_out <= 8'b10000000; end
                endcase
        
            end else if (otype == `OT_INT16) begin // write 16 bits
                case (address[2:1])
                0: begin
                    write_data_out <= write_data;
                    write_enable_out <= 8'b00000011; end 
                1: begin
                    write_data_out <= {write_data[15:0],16'b0};
                    write_enable_out <= 8'b00001100; end 
                2: begin
                    write_data_out <= {write_data[15:0],32'b0};
                    write_enable_out <= 8'b00110000; end 
                3: begin
                    write_data_out <= {write_data[15:0],48'b0};
                    write_enable_out <= 8'b11000000; end 
                endcase
        
            end else if (otype == `OT_INT32 || otype == `OT_FLOAT32) begin // write 32 bits
                case (address[2])
                0: begin
                    write_data_out <= write_data;
                    write_enable_out <= 8'b00001111; end 
                1: begin
                    write_data_out <= {write_data[31:0],32'b0};
                    write_enable_out <= 8'b11110000; end 
                endcase
        
            end else begin // write 64 bits (or more)
                write_data_out <= write_data;
                write_enable_out <= 8'b11111111; 
            end
         
        end else if (rs_status_in == `REG_POINTER & !address_instruction) begin
    
            // memory read. Must have natural alignment
            //read_enable_out <= valid_in & !mask_off & !array_error & !waiting& (tag_val_out != tag_val_in | last_stall);
            read_enable_out <= valid_in & !mask_off & !array_error & !waiting & !stall_in
             & (tag_val_out != tag_val_in | (last_stall & !stall_in));
            
            write_enable_out <= 0;
            case (otype) 
            `OT_INT8:    read_data_size_out <= `OT_INT8;
            `OT_INT16:   read_data_size_out <= `OT_INT16;
            `OT_INT32, 
            `OT_FLOAT32: read_data_size_out <= `OT_INT32;
            default:     read_data_size_out <= `OT_INT64;
            endcase
        
        end
    
        // sort operand values, selected by the priority order: immediate, memory, rt, rs, ru, rd
        operand1_out <= 0;    // value of first operand,  bit `RB indicates invalid
        operand2_out <= 0;    // value of second operand, bit `RB indicates invalid
        operand3_out <= 0;    // value of last operand,   bit `RB indicates invalid
        
        if (immediate_field_in != `IMMED_NONE && rs_status_in == `REG_POINTER) begin
            // both memory and immediate operands.
            // Last operand is an immediate value calculated below.
            // Next to last operand is a memory operand retrieved later.
            // Find remaining register operand
            if      (rt_status_in == `REG_OPERAND) operand1_out <= rt_val;
            else if (ru_status_in == `REG_OPERAND) operand1_out <= ru_val;
            else if (rd_status_in == `REG_OPERAND) operand1_out <= rd_val;
            
        end else if (immediate_field_in != `IMMED_NONE || rs_status_in == `REG_POINTER) begin
            // Last operand is an immediate value calculated below or a memory operand retrieved later.
            // Find remaining register operands
            if  (rt_status_in == `REG_OPERAND) begin 
                operand2_out <= rt_val;
                if      (rs_status_in == `REG_OPERAND) operand1_out <= rs_val;
                else if (ru_status_in == `REG_OPERAND) operand1_out <= ru_val;
                else if (rd_status_in == `REG_OPERAND) operand1_out <= rd_val;
                else operand1_out <= rt_val;  // possible fallback
            end else if (rs_status_in == `REG_OPERAND || rs_status_in == `REG_SYSTEM) begin
                operand2_out <= rs_val;
                if      (ru_status_in == `REG_OPERAND) operand1_out <= ru_val;
                else if (rd_status_in == `REG_OPERAND) operand1_out <= rd_val;
                else operand1_out <= rs_val; // possible fallback_use_in == `FALLBACK_RS
            end else if (ru_status_in == `REG_OPERAND) begin 
                operand2_out <= ru_val;
                if      (rd_status_in == `REG_OPERAND) operand1_out <= rd_val;
                else operand1_out <= ru_val;
            end else if (rd_status_in == `REG_OPERAND) begin
                operand2_out <= rd_val;
                operand1_out <= rd_val;
            end
        end else begin
            // last operand is a register
            if  (rt_status_in == `REG_OPERAND) begin
                operand3_out <= rt_val;            
                if  (rs_status_in == `REG_OPERAND) begin
                    operand2_out <= rs_val;
                    if      (ru_status_in == `REG_OPERAND) operand1_out <= ru_val;
                    else if (rd_status_in == `REG_OPERAND) operand1_out <= rd_val;
                    else operand1_out <= rs_val;
                end else if (ru_status_in == `REG_OPERAND) begin
                    operand2_out <= ru_val;
                    if      (rd_status_in == `REG_OPERAND) operand1_out <= rd_val;
                    else operand1_out <= ru_val;            
                end else if (rd_status_in == `REG_OPERAND) begin
                    operand2_out <= rd_val;
                    operand1_out <= rd_val;
                end            
            end else if (rs_status_in == `REG_OPERAND) begin
                operand3_out <= rs_val;
                if  (ru_status_in == `REG_OPERAND) begin
                    operand2_out <= ru_val;
                    if (rd_status_in == `REG_OPERAND) operand1_out <= rd_val;
                    else operand1_out <= ru_val;            
                end else if (rd_status_in == `REG_OPERAND) begin
                    operand2_out <= rd_val;
                    operand1_out <= rd_val;
                end            
            end else if (ru_status_in == `REG_OPERAND) begin // should not occur
                operand3_out <= ru_val;
                if  (rd_status_in == `REG_OPERAND) begin
                    operand2_out <= rd_val;
                    operand1_out <= rd_val;
                end else begin
                    operand1_out <= ru_val;
                end            
            end else if (rd_status_in == `REG_OPERAND) begin
                operand3_out <= rd_val;
                operand1_out <= rd_val;
            end
        end
        
        // look for immediate operand, and process it if necessary
        if (immediate_field_in != `IMMED_NONE) begin
            if (immediate_field_in == `IMMED_1) begin  // sign_extend 8 bit immediate operand
                if (format_in == `FORMAT_E) begin
                    operand3_out <= {{(`RB-8){instruction_in[`IM5EXS]}},instruction_in[`IM5EX]};
                end else if (format_in == `FORMAT_C && category_in == `CAT_JUMP) begin 
                    // jump in format 1.7C and 2.5.4C
                    operand3_out <= {{(`RB-8){instruction_in[15]}},instruction_in[15:8]};
                end else begin   // format B
                    operand3_out <= {{(`RB-8){instruction_in[`IM1S]}},instruction_in[`IM1]};
                end
            end
            if (immediate_field_in == `IMMED_2) begin // sign_extend 16 bit immediate operand
                if (format_in == `FORMAT_C) begin     // format C: sign extend (IM2,IM1)
                    operand3_out <= {{(`RB-16){instruction_in[15]}},instruction_in[15:0]};
                    // special cases
                    if (mode == 1) begin
                        if (op1 == `II_MOVEU11) operand3_out <= instruction_in[15:0]; // zero extended                        
                        if (op1 == `II_ADDSHIFT16_11) begin
                            `ifdef SUPPORT_64BIT
                                operand3_out <= {{(`RB-32){instruction_in[15]}},instruction_in[15:0],16'b0}; // shift left by 16
                            `else
                                operand3_out <= {instruction_in[15:0],16'b0}; // shift left by 16
                            `endif
                        end
                        if ((op1 & -2) == `II_SHIFT_MOVE_11 || op1 >= `II_SHIFT_ADD_11 && op1 <= `II_SHIFT_XOR_11+1) begin // IM2 << IM1
                            if (instruction_in[`IM1] >= 64) operand3_out <= 0; 
                            else operand3_out <= {{(`RB-8){instruction_in[15]}},instruction_in[15:8]} << instruction_in[5:0];
                        end
                    end
                end else begin        
                    operand3_out <= {{(`RB-16){instruction_in[`IM4S]}},instruction_in[`IM4]};
                    // special cases
                    if (il == 2 && ((mode == 0 && !M) || mode == 2) && mode2 == 7 && !option_bits_im5) begin
                         // format 2.0.7 and 2.2.7 have shift
                        operand3_out <= {{(`RB-16){instruction_in[47]}},instruction_in[`IM4]} << instruction_in[`IM5];
                    end
                end
            end
            if (immediate_field_in == `IMMED_3) begin
                `ifdef SUPPORT_64BIT
                if (il == 3 && ((mode == 0 && !M) || mode == 2) && mode2 == 7 && otype < `OT_FLOAT32) begin
                     // format 3.0.7 and 3.2.7 have shift
                    operand3_out <= {{32{instruction_in[95]}},instruction_in[95:64]} << instruction_in[`IM4];
                end else if (il == 3 && format_in == `FORMAT_E) begin 
                    // other format 3E
                    operand3_out <= {{32{instruction_in[95]}},instruction_in[95:64]};
                end else if (il == 3 && mode == 0 && M) begin 
                    // format 3.8
                    operand3_out <= instruction_in[95:32];
                end else begin
                    // format 2.x
                    operand3_out <= {{32{instruction_in[63]}},instruction_in[63:32]};
                end
                `else
                if (((mode == 0 && !M) || mode == 2) && mode2 == 7 && otype < `OT_FLOAT32) begin
                     // format 3.0.7 and 3.2.7 have shift
                    operand3_out <= instruction_in[95:64] << instruction_in[`IM4];
                end else if (il == 3 && format_in == `FORMAT_E) begin 
                    operand3_out <= instruction_in[95:64];
                end else begin
                    operand3_out <= instruction_in[63:32];
                end                
                `endif                
                
                // special cases
                if (il == 2 && mode == 1 && M) begin 
                    if (op1 == `II_ADDU_29 || op1 == `II_SUBU_29) begin
                        operand3_out <= instruction_in[63:32]; // zero extend
                    end
                    if (op1 == `II_MOVE_HI_29 || (op1 >= `II_ADD_HI_29 && op1 <= `II_XOR_HI_29)) begin 
                        // immediate constant is high word of 64 bits
                        `ifdef SUPPORT_64BIT
                            operand3_out <= {instruction_in[63:32],32'b0}; // high word
                        `else
                            operand3_out <= 0; // there is no high word
                        `endif
                    end
                end
            end
            //if (category_in == `CAT_JUMP) begin // unnecessary check
            if (il == 2 && mode == 5) begin
                // immediate operands in jump instructions 2.5.x
                if (op1 == 0) begin
                    // format 2.5.0A: jump with three registers, and 24 bit jump offset, no immediate            
                end else if (op1 == 1) begin
                    // format 2.5.1B: jump with one register, one 16 bit operand, and 16 bit jum offset            
                    operand3_out <= {{48{instruction_in[47]}},instruction_in[47:32]}; // sign extend 16 bit operand
                end else if (op1 == 4) begin
                    // format 2.5.4C: jump with one register, one 8 bit operand, and 32 bit offset
                    operand3_out <= {{56{instruction_in[15]}},instruction_in[15:8]}; // sign extend 8 bit operand                
                end else if (op1 == 5) begin                
                    // format 2.5.5: jump with one register, one 32 bit operand, and 8 bit offset
                    operand3_out <= {{32{instruction_in[63]}},instruction_in[63:32]}; // sign extend 32 bit operand
                end else if (op1 == 7) begin
                    // format 2.5.7: system call. 16 bit and 32 bit constants
                    operand3_out <= {instruction_in[63:32],16'b0,instruction_in[15:0]}; // 32 bit module ID, 16 bit function ID
                end
            end
            if (il == 3 && mode == 1) begin
                // immedate operands in jump instructions 3.1.x
                if (op1 == 0) begin
                    // format 3.1.0: jump with memory operand and 32 bit offset. no immediate            
                end else if (op1 == 1) begin // && op1 == `IJ_SYSCALL
                    // jump format 3.1.1
                    if (instruction_in[5:0] < `IJ_SYSCALL) begin
                        operand3_out <= instruction_in[95:64];
                    end else begin                
                        // format 3.1.1: system call with 32 bit module ID and 32 bit function ID
                        `ifdef  SUPPORT_64BIT                        
                            operand3_out <= instruction_in[95:32];
                        `else
                            operand3_out <= {instruction_in[79:64],instruction_in[47:32]};
                        `endif
                    end
                end
            end
            operand3_out[`RB] <= 0;    // indicate not missing            
        end
            
        if (address_instruction) begin 
            operand3_out <= address;   // address instruction
        end
        
        if (fallback_use_in > `FALLBACK_SOURCE) begin
            // separate fallback register. Check if fallback zero
            if (fallback_use_in == `FALLBACK_RU && instruction_in[`RU] == 31) operand1_out <= 0;
            if (fallback_use_in == `FALLBACK_RS && instruction_in[`RS] == 31) operand1_out <= 0;
            if (fallback_use_in == `FALLBACK_RT && instruction_in[`RT] == 31) operand1_out <= 0;
        end
        
        
        // output everything else        
        mask_val_out      <= rm_val;
        instruction_pointer_out <= instruction_pointer_in;    // address of current instruction
        instruction_out      <= instruction_in[63:0];         // first two words of instruction
        tag_val_out          <= tag_val_in;                   // instruction tag value
        vector_out           <= vector_in;                    // this is a vector instruction
        category_out         <= category_in;                  // 00: multiformat, 01: single format, 10: jump
        format_out           <= format_in;                    // 00: format A, 01: format E, 10: format B, 11: format C (format D never goes through decoder)
        mask_status_out      <= mask_status_in == `REG_OPERAND;// mask register is used
        mask_alternative_out <= mask_alternative_in;          // mask register and fallback register used for alternative purposes
        fallback_use_out     <= fallback_use_in;              // use of fallback register
        num_operands_out     <= num_operands_in;              // number of source operands
        result_type_out      <= result_type_in;               // type of result: 0: register, 1: system register, 2: memory, 3: other or nothing
        offset_field_out     <= offset_field_in;              // address offset. 0: none, 1: 8 bit, possibly scaled, 2: 16 bit, 3: 32 bit
        immediate_field_out  <= immediate_field_in;           // immediate data field. 0: none, 1: 8 bit, 2: 16 bit, 3: 32 or 64 bit
        scale_factor_out     <= scale_factor_in;              // 00: index is not scaled, 01: index is scaled by operand size, 10: index is scaled by -1
        memory_operand_out   <= (rs_status_in >= `REG_POINTER) && !address_instruction; // The instruction has a memory operand
        array_error_out      <= array_error;                  // Array index exceeds limit;
        options5_out         <= option_bits_im5;              // IM5 used for option bits

    end else begin
    
        // The output is stalled. The instruction in the output buffers must be kept,
        // but we can update the operands if missing values appear on the result buses during a stall.
        // We are saving a lot of flip-flops by using the output buffers for sampling register values
        // from the result buses rather than using separate buffers for this purpose in the next pipeline stage.
        
        if (operand1_out[`RB]) begin // operand 1 missing. watch result busses
            if      (write_en1 && operand1_out[`TAG_WIDTH-1:0] == write_tag1_in) operand1_out <= {1'b0, writeport1_in};
            else if (write_en2 && operand1_out[`TAG_WIDTH-1:0] == write_tag2_in) operand1_out <= {1'b0, writeport2_in};
        end            
        if (operand2_out[`RB]) begin // operand 2 missing. watch result busses
            if      (write_en1 && operand2_out[`TAG_WIDTH-1:0] == write_tag1_in) operand2_out <= {1'b0, writeport1_in};
            else if (write_en2 && operand2_out[`TAG_WIDTH-1:0] == write_tag2_in) operand2_out <= {1'b0, writeport2_in};
        end
        if (operand3_out[`RB]) begin // operand 3 missing. watch result busses
            if      (write_en1 && operand3_out[`TAG_WIDTH-1:0] == write_tag1_in) operand3_out <= {1'b0, writeport1_in};
            else if (write_en2 && operand3_out[`TAG_WIDTH-1:0] == write_tag2_in) operand3_out <= {1'b0, writeport2_in};
        end            
        if (mask_val_out[`MASKSZ]) begin // mask operand missing. watch result busses
            if      (write_en1 && mask_val_out[`TAG_WIDTH-1:0] == write_tag1_in) mask_val_out <= {1'b0, writeport1_in[`MASKSZ-1:0]};
            else if (write_en2 && mask_val_out[`TAG_WIDTH-1:0] == write_tag2_in) mask_val_out <= {1'b0, writeport2_in[`MASKSZ-1:0]};
        end
    end    
end


always_ff @(posedge clock) if (clock_enable) begin
    
    // temporary debug outputs
    debug1_out <=  {address_offset[7:0], address_index[7:0], base_pointer[15:0]};
    debug2_out <=  write_data; 
    
    
    debug3_out[0] <= waiting;
    debug3_out[1] <= stall_in;
    debug3_out[2] <= last_stall;
    debug3_out[3] <= new_instruction;
    
    debug3_out[5:4] <= rd_status_in;
    debug3_out[6] <= wait_next1234;
    debug3_out[7] <= mask_off;

    //debug3_out[8] <= last_valid;
    debug3_out[9] <= last_stall;
    //debug3_out[10] <= current_valid;
    debug3_out[11] <= option_bits_im5;    
    
    debug3_out[12] <= valid_in;
    debug3_out[13] <= valid_out; // preceding valid out
    debug3_out[14] <= 0;
    debug3_out[15] <= div_in;
    
    debug3_out[23:16] <= tag_val_in;
    debug3_out[31:24] <= rd_val;
    
end

endmodule
