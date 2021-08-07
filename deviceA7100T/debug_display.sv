//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog 
// 
// Create date:    2020-06-29
// Last modified:  2021-07-01
// Module name:    debug_display
// Project name:   ForwardCom soft core 
// Target device:  Artix 7 - Nexys A7-100T
// Tool versions:  Vivado 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    showing each stage of the pipeline on LCD displays during debugging
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"

module debug_display (
    input clock,  // system clock (100 MHz)
    input clock_enable, // clock enable. Used when single-stepping
    input reset_button_debounced,           // reset button      
    // from fetch stage
    input [63:0] fetch_instruction,         // first words of instruction
    input [15:0] fetch_instruction_pointer, // point to current instruction
    input        fetch_valid,               // output from fetch is ready
    input        fetch_jump,                // jump instruction bypassing pipeline
    input        fetch_call_e,              // executing call instruction
    input        fetch_return_e,            // executing return instruction    
    input        registerread_stall_predict,// address generation stalled next
    input        addrgen_stall_next,        // address generation stalled next
    input        dataread_stall_predict,    // alu stalled next
    input        alu_stall_next,            // alu stalled next
    input        muldiv_stall_next,         // muldiv stalled next
    input        inout_stall_next,          // in_out_ports stalled next
    
    // from decoder
    input [63:0] decoder_instruction,       // first words of instruction    
    input [15:0] decoder_instruction_pointer,// address of current instruction
    input        decoder_valid,             // output from decoder is ready
    
    // from register_read
    input [63:0] registerread_instruction,  // first words of instruction    
    input [15:0] registerread_instruction_pointer, // address of current instruction
    input        registerread_valid,        // output from decode_wait is ready
    
    // from address generator
    input [63:0] addrgen_instruction,       // first words of instruction    
    input [15:0] addrgen_instruction_pointer,// address of current instruction
    input        addrgen_valid,             // output from addrgen is ready
    
    // from data read
    input [63:0]  dataread_instruction,     // first words of instruction    
    input [15:0]  dataread_instruction_pointer, // address of current instruction
    input [6:0]   dataread_opx,             // operation ID in execution unit. This is mostly equal to op1 for multiformat instructions
    input         dataread_valid,           // output from addrwait is ready
    input [`RB:0] dataread_operand1,        // first register operand RD or RU
    input [`RB:0] dataread_operand2,        // second register operand RS
    input [`RB:0] dataread_operand3,        // last register operand RT
    input [`MASKSZ:0] dataread_mask_val,    // mask value
    input [15:0]  ram_data_in,             // memory operand from data ram
    input         dataread_opr2_from_ram,   // value of operand 2 comes from data ram
    input         dataread_opr3_from_ram,   // value of last operand comes from data ram    

    // from ALU    
    //input [6:0]  writea1,                 // register to write
    input [31:0] alu_result,                // result from ALU
    input [`TAG_WIDTH-1:0] write_tag1,      // instruction tag on result bus
    input        alu_valid,                 // output from alu is ready
    input        alu_jump,                  // jump instruction: jump taken
    //input        alu_nojump,              // jump instruction: jump not taken
    input [15:0] alu_jump_pointer,          // jump target address
    
    // from muldiv result buses
    input [31:0] writeport2,                // result bus 2 from muldiv etc.
    input        write_en2,
    input [`TAG_WIDTH-1:0] write_tag2,    
    
    // output to LCD display driver
    output reg lcd_rs,                      // LCD RS pin
    output reg [1:0] lcd_e,                 // enable pins for two LCD displays
    output reg [3:0] lcd_data               // LCD data, 4 bit bus    
);

// LCD display data
reg [3:0] row;                              // row number (0 = top, 7 = bottom, 8 = finished)
reg [4:0] column;                           // column number (0 = left)
reg [7:0] display_text[0:19];               // text for one line
reg [4:0] text_length;                      // length of text
reg       display_write;                    // write command for display
reg       eol;                              // pad with spaces until end of line
reg       display_ready;                    // display ready for next line
reg [1:0] state;        // 0: idle
                        // 1: set text. send display_write signal to LCD driver
                        // 2: wait for display ready
                        // 3: row++
reg [2:0]  delay;                           // delay for display_write signal

reg [63:0] alu_instruction;                 // first word of instruction currently in ALU
reg [15:0] alu_instruction_pointer;         // address of instruction currently in ALU
reg [6:0]  alu_opx;                         // operation ID in alu
reg [7:0]  instruction_name[0:5];           // name of instruction
reg [15:0] opr1_val;                        // first operand RD or RU
reg [15:0] opr2_val;                        // second operand RS
reg [15:0] opr3_val;                        // third operand RT, immediate, or memory
reg        mask_val;                        // mask register value, bit 0


// LCD display driver
lcd lcd_inst (
    .clock(clock),                          // system clock 100 MHz
    .reset(reset_button_debounced),         // reset and clear
    .x(column),                             // column number (0 = left)
    .y(row[2:0]),                           // row number (0 = top)
    .text(display_text),                    // text for one line
    .text_length(text_length),              // length of text
    .start(display_write),                  // start writing
    .eol(eol),                              // pad with spaces until end of line
    .lcd_rs(lcd_rs),                        // LCD RS pin
	.lcd_e(lcd_e),                            // enable pins for two LCD displays
	.lcd_data(lcd_data),                      // LCD data, 4 bit bus
	.ready(display_ready)                     // finished writing line on display. ready for next line
);

logic [63:0] instruction;                   // first word of instruction for selected pipeline stage    
logic [15:0] instruction_pointer;           // address of instruction for selected pipeline stage
logic       valid;                          // valid output from current stage is ready
logic       stalled;                        // current stage is stalled
logic [1:0] il;                             // instruction length
logic [2:0] mode;                           // format mode
logic [5:0] op1;                            // instruction op1 code
logic [1:0] op2;                            // instruction op2 code
logic       M;                              // format M bit
logic [2:0] mode2;                          // format mode2
logic [2:0] mask;                           // mask register
logic [5:0] opj;                            // jump condition id
logic [6:0] opx;                            // instruction id
reg   [1:0] category;                       // 00: multiformat, 01: single format, 10: jump
reg   [6:0] opx2;                           // instruction id, calculated here
reg   [2:0] format;                         // 1 - 5 means A - E
reg         is_vector;                      // vector instruction


// convert 4-bit binary number to hexadecimal ascii code
function [7:0] nibble2ascii;
    input [3:0] inp;
    logic [7:0] a;
    if (inp < 10) a = inp + 8'H30;
    else a = inp + 8'H37;
    return a;    
endfunction


// multiplexer to select data from one pipeline stage
always_comb begin
    case (row)
    0: begin  // fetch
        instruction = fetch_instruction;
        instruction_pointer = fetch_instruction_pointer;
        opx = opx2;
        valid = fetch_valid;
        stalled = registerread_stall_predict | addrgen_stall_next | dataread_stall_predict;    
    end
    1: begin  // decoder
        instruction = decoder_instruction;
        instruction_pointer = decoder_instruction_pointer;    
        opx = opx2;    
        valid = decoder_valid;    
        stalled = registerread_stall_predict | addrgen_stall_next | dataread_stall_predict;    
    end
    2: begin  // register_read
        instruction = registerread_instruction;
        instruction_pointer = registerread_instruction_pointer;    
        opx = opx2;    
        valid = registerread_valid;    
        stalled = registerread_stall_predict | addrgen_stall_next | dataread_stall_predict | alu_stall_next | inout_stall_next | muldiv_stall_next;
    end
    3: begin  // address generator
        instruction = addrgen_instruction;
        instruction_pointer = addrgen_instruction_pointer;    
        opx = opx2;    
        valid = addrgen_valid;    
        stalled = dataread_stall_predict | alu_stall_next | muldiv_stall_next | inout_stall_next;    
    end
    4: begin  // data read
        instruction = dataread_instruction;
        instruction_pointer = dataread_instruction_pointer;
        opx = dataread_opx;    
        valid = dataread_valid;    
        stalled = dataread_stall_predict | alu_stall_next | muldiv_stall_next | inout_stall_next;    
    end    
    default: begin // alu
        instruction = alu_instruction;
        instruction_pointer = alu_instruction_pointer;
        opx = alu_opx;
        valid = alu_valid;    
        stalled = dataread_stall_predict;    
    end
    endcase

    il = instruction[`IL];        // instruction length
    mode = instruction[`MODE];    // format mode
    mode2 = instruction[`MODE2];  // format mode2
    op1 = instruction[`OP1];      // instruction OP1
    op2 = instruction[`OP2];      // instruction OP2
    M   = instruction[`M];        // format M bit
    mask = instruction[`MASK];    // mask field
    
    // get opj. This code is copied from dataread.sv
    opj = 0;
    if (il == 1) begin
        opj = op1;
    end else if (op1 == 0) begin  // format 2.5.0A, 3.1.0A
        opj = instruction[61:56]; // opj in byte 7
    end else if (il == 2 && op1 == 7) begin // system call
        opj = `IJ_SYSCALL;
    end else if (op1 < 8) begin
        opj = instruction[5:0];
    end else begin
        opj = 56;                 // unknown 
    end
    
end

// state machine for writing one line for each pipeline stage on LCD display
always_ff @(posedge clock) begin
    // state control    
    if (state == 0) begin
        // state 0: idle
        display_write <= 0;
        row <= 0;
        if (clock_enable) begin
            delay <= 3;
            state <= 1;
        end
    
    end else if (state == 1) begin
        // state 1: set text. send display_write pulse
        if (delay < 2) display_write <= 1;
        else display_write <= 0;
        if (delay > 0) begin
            delay <= delay - 1;
        end else begin
            state <= 2;
            delay <= 3;
        end 
        
    end else if (state == 2) begin
        // state 2: wait for display_ready
        if (delay > 0) begin
            delay <= delay - 1;
        end else begin
            if (display_ready) state <= 3;
        end

    end else begin
        // state 3: row++
        if (row < 7) begin
            row <= row + 1;
            state <= 1;
            delay <= 3;
        end else begin
            row <= 0;
            state <= 0;
        end
    end
    
    // compose text for current row
    if (state == 1 || state == 2) begin
    
        if (row < 6) begin
            // First 6 rows: fetch, decode, decodewait, addrgen, addrwait, alu
            case (row)  // Indicate pipeline stage
            0: display_text[0] <= "F";  // fetch
            1: display_text[0] <= "D";  // decode
            2: display_text[0] <= "R";  // register read
            3: display_text[0] <= "A";  // address
            4: display_text[0] <= "d";  // data read
            5: display_text[0] <= "X";  // alu (Execute)            
            endcase
            display_text[1] <= " ";
            //if (1/*valid*/) begin
             
            // write lower 4 digits of instruction_pointer
            display_text[2] <= nibble2ascii(instruction_pointer[15:12]); 
            display_text[3] <= nibble2ascii(instruction_pointer[11:8]); 
            display_text[4] <= nibble2ascii(instruction_pointer[7:4]); 
            display_text[5] <= nibble2ascii(instruction_pointer[3:0]);
            display_text[6] <= stalled ? "#" : " "; 
                
            if (!valid) begin
                display_text[7] <= "-"; 
                text_length <= 8;                
            end else begin
                
                // write il.mode.op1, Format, Operand type, instruction name
                display_text[7] <= nibble2ascii(il); 
                display_text[8] <= "."; 
                if (mode < 2 && M && (!il[0] || !mode[0])) begin
                    // format 0.8, 0.9, 1.8, 2.8, 2.9, 3.8 ½                
                    display_text[9] <= nibble2ascii(mode | 4'b1000);
                end else begin                
                    display_text[9] <= nibble2ascii(mode);
                end 
                // write format letter
                display_text[10] <= {5'b01000,format}; // format letter A - E
                display_text[11] <= " ";
                // write oprand type: bhwdqFDQ
                if (opx == `II_NOP) begin
                    display_text[12] <= " ";
                end else if (is_vector) begin 
                    case (instruction[`OT])
                    0: display_text[12] <= "b"; // byte (8 bit)
                    1: display_text[12] <= "h"; // half word (16 bit)
                    2: display_text[12] <= "w"; // word (32 bit)
                    3: display_text[12] <= "d"; // double word (64 bit)
                    4: display_text[12] <= "q"; // quad word (128 bit)
                    5: display_text[12] <= "F"; // float single precision (32 bit)
                    6: display_text[12] <= "D"; // double precision (64 bit)
                    7: display_text[12] <= "Q"; // quadruple precision (128 bit)
                    endcase
                end else begin
                    case (instruction[14:13])   // two bit operand type for non-vector instructions
                    0: display_text[12] <= "b"; // byte (8 bit)
                    1: display_text[12] <= "h"; // half word (16 bit)
                    2: display_text[12] <= "w"; // word (32 bit)
                    3: display_text[12] <= "d"; // double word (64 bit)
                    endcase            
                end
                display_text[13] <= " ";
                    
                // write name of instruction
                for (int i = 0; i < 6; i++) begin
                    display_text[i+14] <= instruction_name[i];
                end                
                text_length <= 20;
            end
                
            if (row == 0 && fetch_jump) begin
                // jump, call or return bypassign pipeline 
                if (fetch_call_e) begin
                    display_text[0] <= "C";            
                    display_text[1] <= "a";
                    display_text[2] <= "l";
                    display_text[3] <= "l";
                    text_length <= 4;
                end else if (fetch_return_e) begin
                    display_text[0] <= "R";            
                    display_text[1] <= "e";
                    display_text[2] <= "t";
                    display_text[3] <= "u";                
                    display_text[4] <= "r";                
                    display_text[5] <= "n";                
                    text_length <= 6;
            end else begin                   
                    display_text[0] <= "J";            
                    display_text[1] <= "u";
                    display_text[2] <= "m";
                    display_text[3] <= "p";
                    text_length <= 4;
                end
            end
                 
            column <= 0;
            eol <= 1;
            
        end else if (row == 6) begin
            // row 6: operands
            display_text[0] <= ":";  // operands            
            display_text[1] <= " ";
            display_text[2] <= nibble2ascii(opr1_val[15:12]); 
            display_text[3] <= nibble2ascii(opr1_val[11:8]); 
            display_text[4] <= nibble2ascii(opr1_val[7:4]); 
            display_text[5] <= nibble2ascii(opr1_val[3:0]);
            display_text[6] <= " "; 
            display_text[7] <= nibble2ascii(opr2_val[15:12]); 
            display_text[8] <= nibble2ascii(opr2_val[11:8]); 
            display_text[9] <= nibble2ascii(opr2_val[7:4]); 
            display_text[10] <= nibble2ascii(opr2_val[3:0]);
            display_text[11] <= " "; 
            display_text[12] <= nibble2ascii(opr3_val[15:12]); 
            display_text[13] <= nibble2ascii(opr3_val[11:8]); 
            display_text[14] <= nibble2ascii(opr3_val[7:4]); 
            display_text[15] <= nibble2ascii(opr3_val[3:0]);
            display_text[16] <= " "; 
            text_length <= 17; 
            column <= 0;
            eol <= 1;
        
        end else if (row == 7 & valid) begin
            // row 7: result
            column <= 0;
            eol <= 1;
            display_text[0] <= "=";  // result            
            display_text[1] <= " "; 

            if (category == `CAT_JUMP) begin  // result of jump instruction
                display_text[2] <= nibble2ascii(alu_result[15:12]); 
                display_text[3] <= nibble2ascii(alu_result[11:8]); 
                display_text[4] <= nibble2ascii(alu_result[7:4]); 
                display_text[5] <= nibble2ascii(alu_result[3:0]);
                display_text[6] <= " ";
                if (alu_jump) begin // jump taken
                    display_text[7]  <= "j";
                    display_text[8]  <= "u";
                    display_text[9]  <= "m";
                    display_text[10] <= "p";
                    display_text[11] <= " "; // write target address:
                    display_text[12] <= nibble2ascii(alu_jump_pointer[15:12]); 
                    display_text[13] <= nibble2ascii(alu_jump_pointer[11:8]); 
                    display_text[14] <= nibble2ascii(alu_jump_pointer[7:4]); 
                    display_text[15] <= nibble2ascii(alu_jump_pointer[3:0]);                
                    text_length <= 16;
                end else begin // jump not taken
                    display_text[7]  <= "n";
                    display_text[8]  <= "o";
                    display_text[9]  <= " ";
                    display_text[10] <= "j";
                    display_text[11] <= "u";
                    display_text[12] <= "m";
                    display_text[13] <= "p";
                    text_length <= 14;                
                end
                
            end else if (write_en2) begin  // result from muldiv or other unit
                // to do: what to do if there are results from alu and muldiv simultaneously?
                display_text[0] <= "m";
                display_text[1] <= "u";
                display_text[2] <= "l";
                display_text[3] <= "d";
                display_text[4] <= "i";
                display_text[5] <= "v";
                display_text[6] <= "=";                
                display_text[7]  <= nibble2ascii(writeport2[31:28]); 
                display_text[8]  <= nibble2ascii(writeport2[27:24]); 
                display_text[9]  <= nibble2ascii(writeport2[23:20]); 
                display_text[10] <= nibble2ascii(writeport2[19:16]);
                display_text[11] <= nibble2ascii(writeport2[15:12]); 
                display_text[12] <= nibble2ascii(writeport2[11:8]); 
                display_text[13] <= nibble2ascii(writeport2[7:4]); 
                display_text[14] <= nibble2ascii(writeport2[3:0]);                
            
            end else begin  // 32 bit result of alu non-jump instruction
                display_text[2] <= nibble2ascii(alu_result[31:28]); 
                display_text[3] <= nibble2ascii(alu_result[27:24]); 
                display_text[4] <= nibble2ascii(alu_result[23:20]); 
                display_text[5] <= nibble2ascii(alu_result[19:16]);
                display_text[6] <= nibble2ascii(alu_result[15:12]); 
                display_text[7] <= nibble2ascii(alu_result[11:8]); 
                display_text[8] <= nibble2ascii(alu_result[7:4]); 
                display_text[9] <= nibble2ascii(alu_result[3:0]);
                if (instruction[`MASK] < 7) begin
                    // write bit 0 of mask
                    display_text[10]  <= " ";
                    display_text[11]  <= "m";
                    display_text[12]  <= "0" | mask_val;
                    text_length <= 13;     
                end else begin // no mask
                    text_length <= 10;
                end          
            end
        end else begin
            // row 7, not valid
            display_text[0]  <= "-";
            text_length <= 1;
            column <= 0;
            eol <= 1;
        end
    end
end


// parallel decoding if instruction is not completely decoded yet
// calculate opx if not available
always_ff @(posedge clock) begin

    // save inputs to alu stage for next clock cycle because they are not output from alu
    if (clock_enable) begin
        alu_instruction <= dataread_instruction;                // first word of instruction currently in ALU
        alu_instruction_pointer <= dataread_instruction_pointer;// address of instruction currently in ALU
        alu_opx  <= dataread_opx;                               // operation ID in alu
        
        // mirror operand catching in ALU stage        
        if (dataread_operand1[`RB]) begin                       // value missing
            if (dataread_operand1[`TAG_WIDTH-1:0] == write_tag1) begin
                opr1_val <= alu_result;                         // got value from result bus 1
            end else if (write_en2 && dataread_operand1[`TAG_WIDTH-1:0] == write_tag2) begin
                opr1_val <= writeport2;                         // obtained from result bus 2
            end else begin
                opr1_val <= 0; 
            end
        end else begin
            opr1_val <= dataread_operand1;
        end 
        
        if (dataread_opr2_from_ram) begin
            opr2_val <= ram_data_in;        
        end else if (dataread_operand2[`RB]) begin              // value missing
            if (dataread_operand2[`TAG_WIDTH-1:0] == write_tag1) begin
                opr2_val <= alu_result;                         // got value from result bus 1
            end else if (write_en2 && dataread_operand2[`TAG_WIDTH-1:0] == write_tag2) begin
                opr2_val <= writeport2;                         // obtained from result bus 2
            end else begin
                opr2_val <= 0; 
            end
        end else begin
            opr2_val <= dataread_operand2;
        end
         
        if (dataread_opr3_from_ram) begin
            opr3_val <= ram_data_in;        
        end else if (dataread_operand3[`RB]) begin              // value missing
            if (dataread_operand3[`TAG_WIDTH-1:0] == write_tag1) begin
                opr3_val <= alu_result;                         // got value from result bus 1
            end else if (write_en2 && dataread_operand3[`TAG_WIDTH-1:0] == write_tag2) begin
                opr3_val <= writeport2;                         // obtained from result bus 2
            end else begin
                opr3_val <= 0; 
            end
        end else begin
            opr3_val <= dataread_operand3;
        end 
        
        if (dataread_mask_val[`MASKSZ]) begin                   // value missing
            if (dataread_mask_val[`TAG_WIDTH-1:0] == write_tag1) begin
                mask_val <= alu_result;                         // got value from result bus 1
            end else if (write_en2 && dataread_mask_val[`TAG_WIDTH-1:0] == write_tag2) begin
                mask_val <= writeport2[31:0];                   // obtained from result bus 2
            end else begin
                mask_val <= 0;
            end
        end else begin // value available
            mask_val <= dataread_mask_val[`TAG_WIDTH-1:0];
        end
    end
    
    if (state == 1 || state == 2) begin
        // detect category, 00: multiformat, 01: single format, 10: jump
        // this code is copied from decoder.sv
        if (il == 0) begin // format 0.x
            category <= `CAT_MULTI;
            
        end else if (il == 1) begin                   // format 1.x
            if (mode == 6 || mode == 7) begin         // format 1.6 and 1.7
                category <= `CAT_JUMP;
            end else begin
                category <= `CAT_SINGLE;
            end
            
        end else if (il >= 2 && ((mode == 0 && !M) || mode == 2) && op2 != 0 && (mode2 != 5 || il == 3)) begin // format 2.0.x, 2.2.x, 3.0.x, 3.2.x, op2 > 0
            category <= `CAT_SINGLE;
            
        end else if (il == 2) begin                   // format 2.x
            if (mode == 1 && M) begin                 // format 2.9
                category <= `CAT_SINGLE;
            end else if (mode == 6 || mode == 7) begin// format 2.6 - 2.7
                category <= `CAT_SINGLE;
            end else if (mode == 5) begin             // format 2.5
                if (op1 < 8) begin
                    category <= `CAT_JUMP;
                end else begin
                    category <= `CAT_SINGLE;
                end            
            end else begin
                category <= `CAT_MULTI;
            end            
        end else begin                                // format 3.x
            if (mode == 1) begin                      // format 3.1
                if (op1 < 8) begin
                    category <= `CAT_JUMP;
                end else begin
                    category <= `CAT_SINGLE;
                end
            end else begin
                category <= `CAT_MULTI;
            end
        end
        
        // detect instruction format: A, B, C, D, or E indicated as 1 - 5
        if (il == 0) begin                            // format 0.x
            if (mode == 1 || mode == 3 || mode == 7) begin
                format <= 2;                          // B: 0.1, 0.3, 0.7, 0.9
            end else begin
                format <= 1;                          // A: 0.0, 0.2, 0.4, 0.5, 0.6, 0.8
            end        
        end else if (il == 1) begin                   // format 1.x
            if (mode == 3 || (mode == 0 && M)) begin
                format <= 2;                          // B: 1.3, 1.8
            end else if (mode == 6) begin             // 1.6 jump instructions
                if (op1 == `II_RETURN) format = 3;    // C: return
                else if (op1 >= `II_JUMP_RELATIVE) begin
                    format <= 1;                      // A: relative jump, sys_call
                end else format <= 2;                 // B
            end else if (mode == 7) begin             // 1.7 jump instructions
                if (op1 < 16) format <= 4;            // 24-bit jump/call, format D
                else format <= 3;                     // other jumps, format C
            end else if (mode == 1 || mode == 4) begin
                format <= 3;                          // C: 1.1, 1.4, 1.7
            end else begin
                format <= 1;                          // A: 1.0, 1.2
            end
        end else if (il == 2) begin                   // format 2.x
            if ((mode == 0 && M == 0) || mode == 2) begin
                format <= 5;                          // E: 2.0.x, 2.2.x
            end else if (mode == 5) begin             // format 2.5 mixed
                if (op1 == 0) begin
                    format <= `FORMAT_A;
                end else if (op1 >= 4 && op1 <= 8) begin
                    format <= `FORMAT_C;              // 2.5 2-4 jump uses format C
                end else if (op1 >= `II_25_VECT) begin     
                    format <= 1;                      // A: 2.5 32-63 vector instructions 
                end else begin
                    format <= 2;                      // B: other jump and miscellaneous instructions 
                end
            end else begin
                format <= 1;                          // A: other jump and miscellaneous instructions 
            end            
        end else begin                                // format 3.x
            if ((mode == 0 && M == 0) || mode == 2) begin
                format <= 5;                          // E: 3.0.x, 3.2.x
            end else if (mode == 1) begin             // 3.1 mixed
                if (op1 < 8) begin                    // jump instructions
                    format <= 2;                      // B
                end else begin
                    format <= 1;                      // A
                end
            end else begin
                format <= 1;                          // A
            end
        end
    end
    
    // is this a vector instruction?
    if (il == 2 && mode == 5) begin                   // 2.5 mixed 
        is_vector <= op1 >= `II_25_VECT;
    end else if (il == 3 && mode == 1) begin          // 3.1 mixed 
        is_vector <= op1 >= `II_31_VECT;
    end else if (category == `CAT_JUMP) begin
        if (il == 1 && mode == 7) is_vector <= 0;     // jump instructions format 1.7C
        is_vector <= M;                               // all other jump instructions
    end else if (mode < 2) begin
        is_vector <= 0;
    end else begin
        is_vector <= 1;
    end    
    
    // calculate opx.
    // This code is copied from addresswait.sv
    if (state == 1 || state == 2) begin
        // convert op1 to opx: operation id in execution unit
        opx2 = `IX_UNDEF;                             // default is undefined
        if (category == `CAT_MULTI) begin
            opx2 = op1;                               // mostly same id for multiformat instructions
            if (op1 == `II_SUB_REV) opx2 = `II_SUB;   // operands have been swapped 
            if (op1 == `II_DIV_REV) opx2 = `II_DIV;   // operands have been swapped
        end else if (il == 1 && mode == 1) begin
            // format 1.1 C. single format with 16 bit constant
            case (op1[5:1])
            `II_ADD11 >> 1:         opx2 = `II_ADD;
            `II_MUL11 >> 1:         opx2 = `II_MUL;
            `II_ADDSHIFT16_11 >> 1: opx2 = `II_ADD;
            `II_SHIFT_MOVE_11 >> 1: opx2 = `II_MOVE;
            `II_SHIFT_ADD_11 >> 1:  opx2 = `II_ADD;
            `II_SHIFT_AND_11 >> 1:  opx2 = `II_AND;
            `II_SHIFT_OR_11 >> 1:   opx2 = `II_OR;
            `II_SHIFT_XOR_11 >> 1:  opx2 = `II_XOR;
            default: opx2 = `IX_UNDEF;
            endcase
            if (op1 <= `II_MOVE11_LAST) opx2 = `II_MOVE; // five different move instructions
            
        end else if (il == 1 && mode == 0 && M) begin
            // format 1.8 B. single format with 8 bit constant
            case (op1)
            `II_SHIFT_ABS18:  opx2 = `IX_ABS;
            `II_BITSCAN_18:   opx2 = `IX_BIT_SCAN;
            `II_ROUNDP2_18:   opx2 = `IX_ROUNDP2;
            `II_POPCOUNT_18:  opx2 = `IX_POPCOUNT;
            `II_READ_SPEC18:  opx2 = `IX_READ_SPEC;
            `II_WRITE_SPEC18: opx2 = `IX_WRITE_SPEC;
            `II_READ_CAP18:   opx2 = `IX_READ_CAPABILITIES;
            `II_WRITE_CAP18:  opx2 = `IX_WRITE_CAPABILITIES;
            `II_READ_PERF18:  opx2 = `IX_READ_PERF;
            `II_READ_PERFS18: opx2 = `IX_READ_PERF;
            `II_READ_SYS18:   opx2 = `IX_READ_SYS;
            `II_WRITE_SYS18:  opx2 = `IX_WRITE_SYS;
            `II_INPUT_18:     opx2 = `IX_INPUT;
            `II_OUTPUT_18:    opx2 = `IX_OUTPUT;            
            endcase
            
        end else if (il == 2 && (mode == 0 && !M || mode == 2) && mode2 == 6) begin
            // format 2.0.6 and 2.2.6
            if (op1 == `II_TRUTH_TAB3 && op2 == `II2_TRUTH_TAB3) opx2 = `IX_TRUTH_TAB3;
            
        end else if (il == 2 && mode == 0 && !M && mode2 == 7) begin
            // format 2.0.7E. single format
            if (op1 == `II_MOVE_BITS && op2 == `II2_MOVE_BITS) opx2 = `IX_MOVE_BITS1;
        end else if (il == 2 && mode == 1 && M) begin
            // format 2.9A. single format with 32 bit constant
            case (op1)
            `II_MOVE_HI_29: opx2 = `II_MOVE;  // shifted left by 32 here. just store result
            `II_INSERT_HI_29: opx2 = `IX_INSERT_HI;
            `II_ADDU_29: opx2 = `II_ADD;
            `II_SUBU_29: opx2 = `II_SUB;
            `II_ADD_HI_29: opx2 = `II_ADD;
            `II_AND_HI_29: opx2 = `II_SUB;
            `II_OR_HI_29: opx2 = `II_OR;
            `II_XOR_HI_29: opx2 = `II_XOR;
            `II_ADDRESS_29: opx2 = `IX_ADDRESS; // address instruction. resolved in this state. just store result
            endcase     
        end    
    end
    
    // get name of instruction
    if (state == 1 || state == 2) begin
        // default characters are space if not specified below
        instruction_name[0] <= " "; 
        instruction_name[1] <= " "; 
        instruction_name[2] <= " "; 
        instruction_name[3] <= " ";            
        instruction_name[4] <= " ";            
        instruction_name[5] <= " ";            

        if (format == 4) begin // format D. 24-bit jump or call
            if (op1 < 8) begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "U"; 
                instruction_name[2] <= "M"; 
                instruction_name[3] <= "P";            
            end else begin
                instruction_name[0] <= "C"; 
                instruction_name[1] <= "A"; 
                instruction_name[2] <= "L"; 
                instruction_name[3] <= "L";
            end
            
        end else if (category == `CAT_JUMP) begin
            case (opj)
            `IJ_SUB_JZ: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "Z";
                end 
            `IJ_SUB_JZ+1: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "Z";
                end 
            `IJ_SUB_JNEG: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                end 
            `IJ_SUB_JNEG+1: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "N"; 
                end
            `IJ_SUB_JPOS: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "P"; 
                end 
            `IJ_SUB_JPOS+1: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "P"; 
                end 
            `IJ_SUB_JOVFLW: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "O"; 
                end 
            `IJ_SUB_JOVFLW+1: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "O"; 
                end 
            `IJ_SUB_JBORROW: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "C"; 
                end                    
            `IJ_SUB_JBORROW+1: begin
                instruction_name[0] <= "-"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "C"; 
                end                    
            `IJ_ADD_JZ: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "Z";
                end 
            `IJ_ADD_JZ+1: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "Z";
                end 
            `IJ_ADD_JNEG: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                end 
            `IJ_ADD_JNEG+1: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "N"; 
                end
            `IJ_ADD_JPOS: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "P"; 
                end 
            `IJ_ADD_JPOS+1: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "P"; 
                end 
            `IJ_ADD_JOVFLW: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "O"; 
                end 
            `IJ_ADD_JOVFLW+1: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "O"; 
                end 
            `IJ_ADD_JCARRY: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "C"; 
                end                    
            `IJ_ADD_JCARRY+1: begin
                instruction_name[0] <= "+"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "C"; 
                end
            `IJ_AND_JZ: begin
                instruction_name[0] <= "&"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "Z"; 
                end                     
            `IJ_AND_JZ+1: begin
                instruction_name[0] <= "&"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "Z"; 
                end
            `IJ_OR_JZ: begin
                instruction_name[0] <= "|"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "Z"; 
                end                     
            `IJ_OR_JZ+1: begin
                instruction_name[0] <= "|"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "Z"; 
                end 
            `IJ_XOR_JZ: begin
                instruction_name[0] <= "^"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "Z"; 
                end                     
            `IJ_XOR_JZ+1: begin
                instruction_name[0] <= "^"; 
                instruction_name[1] <= "J"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "Z"; 
                end                    
            `IJ_COMPARE_JEQ: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "="; 
                instruction_name[2] <= "="; 
                end                     
            `IJ_COMPARE_JEQ+1: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "!"; 
                instruction_name[2] <= "="; 
                end 
            `IJ_COMPARE_JSB: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "s"; 
                instruction_name[2] <= "<"; 
                end                     
            `IJ_COMPARE_JSB+1: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "s"; 
                instruction_name[2] <= ">"; 
                instruction_name[3] <= "="; 
                end 
            `IJ_COMPARE_JSA: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "s"; 
                instruction_name[2] <= ">"; 
                end                     
            `IJ_COMPARE_JSA+1: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "s"; 
                instruction_name[2] <= "<"; 
                instruction_name[3] <= "="; 
                end
            `IJ_COMPARE_JUB: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "u"; 
                instruction_name[2] <= "<"; 
                end                     
            `IJ_COMPARE_JUB+1: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "u"; 
                instruction_name[2] <= ">"; 
                instruction_name[3] <= "="; 
                end 
            `IJ_COMPARE_JUA: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "u"; 
                instruction_name[2] <= ">"; 
                end                     
            `IJ_COMPARE_JUA+1: begin
                instruction_name[0] <= "J"; 
                instruction_name[1] <= "u"; 
                instruction_name[2] <= "<"; 
                instruction_name[3] <= "="; 
                end
            `IJ_TEST_BIT_JTRUE: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "B"; 
                instruction_name[2] <= "I"; 
                instruction_name[3] <= "T"; 
                instruction_name[4] <= "1"; 
                end 
            `IJ_TEST_BIT_JTRUE+1: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "B"; 
                instruction_name[2] <= "I"; 
                instruction_name[3] <= "T"; 
                instruction_name[4] <= "0"; 
                end
            `IJ_TEST_BITS_AND: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "B"; 
                instruction_name[2] <= "I"; 
                instruction_name[3] <= "T"; 
                instruction_name[4] <= "&"; 
                end 
            `IJ_TEST_BITS_AND+1: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "B"; 
                instruction_name[2] <= "I"; 
                instruction_name[3] <= "T"; 
                instruction_name[4] <= "N"; 
                instruction_name[5] <= "&"; 
                end                
            `IJ_TEST_BITS_OR: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "B"; 
                instruction_name[2] <= "I"; 
                instruction_name[3] <= "T"; 
                instruction_name[4] <= "|"; 
                end 
            `IJ_TEST_BITS_OR+1: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "B"; 
                instruction_name[2] <= "I"; 
                instruction_name[3] <= "T"; 
                instruction_name[4] <= "N"; 
                instruction_name[5] <= "|"; 
                end
            `IJ_INC_COMP_JBELOW: begin
                instruction_name[0] <= "I"; 
                instruction_name[1] <= "N"; 
                instruction_name[2] <= "C"; 
                instruction_name[3] <= "J"; 
                instruction_name[4] <= "<"; 
                end
            `IJ_INC_COMP_JBELOW+1: begin
                instruction_name[0] <= "I"; 
                instruction_name[1] <= "N"; 
                instruction_name[2] <= "C"; 
                instruction_name[3] <= "J"; 
                instruction_name[4] <= ">"; 
                instruction_name[5] <= "="; 
                end
            `IJ_INC_COMP_JABOVE: begin
                instruction_name[0] <= "I"; 
                instruction_name[1] <= "N"; 
                instruction_name[2] <= "C"; 
                instruction_name[3] <= "J"; 
                instruction_name[4] <= ">"; 
                end 
            `IJ_INC_COMP_JABOVE+1: begin
                instruction_name[0] <= "I"; 
                instruction_name[1] <= "N"; 
                instruction_name[2] <= "C"; 
                instruction_name[3] <= "J"; 
                instruction_name[4] <= "<"; 
                instruction_name[5] <= "="; 
                end
            `IJ_SUB_MAXLEN_JPOS: begin
                instruction_name[0] <= "L"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "O"; 
                instruction_name[3] <= "P"; 
                instruction_name[4] <= "-"; 
                end  
            `IJ_SUB_MAXLEN_JPOS+1: begin
                instruction_name[0] <= "L"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "O"; 
                instruction_name[3] <= "P"; 
                instruction_name[4] <= "+"; 
                end
            `IJ_RETURN: begin // also sys_return
                instruction_name[0] <= "R"; 
                instruction_name[1] <= "E"; 
                instruction_name[2] <= "T"; 
                instruction_name[3] <= "U"; 
                instruction_name[4] <= "R"; 
                instruction_name[5] <= "N"; 
                end
            `IJ_SYSCALL: begin // also trap
                if (mode == 7) begin // trap
                    instruction_name[0] <= "T"; 
                    instruction_name[1] <= "R"; 
                    instruction_name[2] <= "A"; 
                    instruction_name[3] <= "P"; 
                end else begin// sys_call
                    instruction_name[0] <= "S"; 
                    instruction_name[1] <= "Y"; 
                    instruction_name[2] <= "S"; 
                    instruction_name[3] <= "C"; 
                    instruction_name[4] <= "A"; 
                    instruction_name[5] <= "L"; 
                    end
                end
            default:
                if (opj >= `IJ_JUMP_INDIRECT_MEM) begin 
                    if (opj[0]) begin // indirect call
                        instruction_name[0] <= "C"; 
                        instruction_name[1] <= "A"; 
                        instruction_name[2] <= "L"; 
                        instruction_name[3] <= "L"; 
                        instruction_name[4] <= "i"; 
                    end else begin // indirect jump
                        instruction_name[0] <= "J"; 
                        instruction_name[1] <= "U"; 
                        instruction_name[2] <= "M"; 
                        instruction_name[3] <= "P"; 
                        instruction_name[4] <= "i"; 
                    end
                end else begin
                    // unknown jump instruction
                    instruction_name[0] <= "J"; 
                    instruction_name[1] <= "U"; 
                    instruction_name[2] <= "M"; 
                    instruction_name[3] <= "P"; 
                    instruction_name[4] <= "?"; 
                end
            endcase
        end else begin
            // all other instructions than jump
            case (opx)
            `II_NOP: begin
                instruction_name[0] <= "N"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "P"; 
                end
            `II_MOVE: begin
                instruction_name[0] <= "M"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "V"; 
                instruction_name[3] <= "E"; 
                end                    
            `II_STORE: begin
                instruction_name[0] <= "S"; 
                instruction_name[1] <= "T"; 
                instruction_name[2] <= "O"; 
                instruction_name[3] <= "R"; 
                instruction_name[4] <= "E"; 
                end
            `II_SIGN_EXTEND: begin
                instruction_name[0] <= "S"; 
                instruction_name[1] <= "I"; 
                instruction_name[2] <= "G"; 
                instruction_name[3] <= "H"; 
                instruction_name[4] <= "E"; 
                end
            `II_SIGN_EXTEND_ADD: begin
                instruction_name[0] <= "S"; 
                instruction_name[1] <= "I"; 
                instruction_name[2] <= "G"; 
                instruction_name[3] <= "N"; 
                instruction_name[4] <= "E"; 
                instruction_name[5] <= "+"; 
                end
            `II_COMPARE: begin
                instruction_name[0] <= "C"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "M"; 
                instruction_name[3] <= "P"; 
                end
            `II_ADD: begin
                instruction_name[0] <= "A"; 
                instruction_name[1] <= "D"; 
                instruction_name[2] <= "D"; 
                end
            `II_SUB: begin
                instruction_name[0] <= "S"; 
                instruction_name[1] <= "U"; 
                instruction_name[2] <= "B"; 
                end
            `II_MUL, `II_MUL_HI, `II_MUL_HI_U: // II_MUL_EX, II_MUL_EX_U  
                begin
                instruction_name[0] <= "M"; 
                instruction_name[1] <= "U"; 
                instruction_name[2] <= "L"; 
                end
            `II_DIV, `II_DIV_U: begin
                instruction_name[0] <= "D"; 
                instruction_name[1] <= "I"; 
                instruction_name[2] <= "V"; 
                end
            `II_REM, `II_REM_U: begin
                instruction_name[0] <= "R"; 
                instruction_name[1] <= "E"; 
                instruction_name[2] <= "M"; 
                end
            `II_MIN, `II_MIN_U: begin
                instruction_name[0] <= "M"; 
                instruction_name[1] <= "I"; 
                instruction_name[2] <= "N"; 
                end
            `II_MAX, `II_MAX_U: begin
                instruction_name[0] <= "M"; 
                instruction_name[1] <= "A"; 
                instruction_name[2] <= "X"; 
                end
            `II_AND: begin
                instruction_name[0] <= "A"; 
                instruction_name[1] <= "N"; 
                instruction_name[2] <= "D"; 
                end
            `II_OR: begin
                instruction_name[0] <= "O"; 
                instruction_name[1] <= "R"; 
                end
            `II_XOR: begin
                instruction_name[0] <= "X"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "R"; 
                end
            `II_SHIFT_LEFT: begin // also mul_2pow
                instruction_name[0] <= "S"; 
                instruction_name[1] <= "H"; 
                instruction_name[2] <= "L"; 
                end
            `II_ROTATE: begin
                instruction_name[0] <= "R"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "T"; 
                end
            `II_SHIFT_RIGHT_S, `II_SHIFT_RIGHT_U: begin
                instruction_name[0] <= "S"; 
                instruction_name[1] <= "H"; 
                instruction_name[2] <= "R"; 
                end
            `II_SET_BIT: begin
                instruction_name[0] <= "S"; 
                instruction_name[1] <= "E"; 
                instruction_name[2] <= "T"; 
                instruction_name[3] <= "b"; 
                end
            `II_CLEAR_BIT: begin
                instruction_name[0] <= "C"; 
                instruction_name[1] <= "L"; 
                instruction_name[2] <= "E"; 
                instruction_name[3] <= "A"; 
                instruction_name[4] <= "R"; 
                instruction_name[5] <= "b"; 
                end
            `II_TOGGLE_BIT: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "G"; 
                instruction_name[3] <= "G"; 
                instruction_name[4] <= "L"; 
                instruction_name[5] <= "b"; 
                end
            `II_TEST_BIT: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "E"; 
                instruction_name[2] <= "S"; 
                instruction_name[3] <= "T"; 
                instruction_name[4] <= "b"; 
                end
            `II_TEST_BITS_AND: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "E"; 
                instruction_name[2] <= "S"; 
                instruction_name[3] <= "T"; 
                instruction_name[4] <= "b"; 
                instruction_name[5] <= "&"; 
                end
            `II_TEST_BITS_OR: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "E"; 
                instruction_name[2] <= "S"; 
                instruction_name[3] <= "T"; 
                instruction_name[4] <= "b"; 
                instruction_name[5] <= "|"; 
                end
            `II_ADD_FLOAT16: begin
                instruction_name[0] <= "A"; 
                instruction_name[1] <= "D"; 
                instruction_name[2] <= "D"; 
                instruction_name[3] <= "h"; 
                end
            `II_SUB_FLOAT16: begin
                instruction_name[0] <= "S"; 
                instruction_name[1] <= "U"; 
                instruction_name[2] <= "B"; 
                instruction_name[3] <= "h"; 
                end
            `II_MUL_FLOAT16: begin
                instruction_name[0] <= "M"; 
                instruction_name[1] <= "U"; 
                instruction_name[2] <= "L"; 
                instruction_name[3] <= "h"; 
                end
            `II_MUL_ADD_FLOAT16: begin
                instruction_name[0] <= "M"; 
                instruction_name[1] <= "U"; 
                instruction_name[2] <= "L"; 
                instruction_name[3] <= "A"; 
                instruction_name[4] <= "h"; 
                end
            `II_MUL_ADD, `II_MUL_ADD2: begin
                instruction_name[0] <= "M"; 
                instruction_name[1] <= "U"; 
                instruction_name[2] <= "L"; 
                instruction_name[3] <= "A"; 
                end                
            `II_ADD_ADD: begin
                instruction_name[0] <= "A"; 
                instruction_name[1] <= "D"; 
                instruction_name[2] <= "D"; 
                instruction_name[3] <= "A"; 
                instruction_name[4] <= "D"; 
                instruction_name[5] <= "D"; 
                end                
            `II_SELECT_BITS: begin
                instruction_name[0] <= "S"; 
                instruction_name[1] <= "E"; 
                instruction_name[2] <= "L"; 
                instruction_name[3] <= "E"; 
                instruction_name[4] <= "C"; 
                instruction_name[5] <= "T";
                end                
            `II_FUNNEL_SHIFT: begin
                instruction_name[0] <= "F"; 
                instruction_name[1] <= "U"; 
                instruction_name[2] <= "N"; 
                instruction_name[3] <= "N"; 
                instruction_name[4] <= "E"; 
                instruction_name[5] <= "L";
                end
            `IX_ABS: begin
                instruction_name[0] <= "A"; 
                instruction_name[1] <= "B"; 
                instruction_name[2] <= "S"; 
                end
            `IX_BIT_SCAN: begin
                instruction_name[0] <= "B"; 
                instruction_name[1] <= "S"; 
                instruction_name[2] <= "C"; 
                instruction_name[3] <= "A"; 
                instruction_name[4] <= "N"; 
                end
            `IX_ROUNDP2: begin
                instruction_name[0] <= "R"; 
                instruction_name[1] <= "N"; 
                instruction_name[2] <= "D"; 
                instruction_name[3] <= "P"; 
                instruction_name[4] <= "2"; 
                end
            `IX_POPCOUNT: begin
                instruction_name[0] <= "P"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "P"; 
                instruction_name[3] <= "C"; 
                instruction_name[4] <= "N"; 
                instruction_name[5] <= "T"; 
                end
            `IX_READ_SPEC: begin
                instruction_name[0] <= "R"; 
                instruction_name[1] <= "D"; 
                instruction_name[2] <= " "; 
                instruction_name[3] <= "S"; 
                instruction_name[4] <= "P"; 
                instruction_name[5] <= "C"; 
                end
            `IX_WRITE_SPEC: begin
                instruction_name[0] <= "W"; 
                instruction_name[1] <= "R"; 
                instruction_name[2] <= " "; 
                instruction_name[3] <= "S"; 
                instruction_name[4] <= "P"; 
                instruction_name[5] <= "C"; 
                end
            `IX_READ_CAPABILITIES: begin
                instruction_name[0] <= "R"; 
                instruction_name[1] <= "D"; 
                instruction_name[2] <= " "; 
                instruction_name[3] <= "C"; 
                instruction_name[4] <= "A"; 
                instruction_name[5] <= "P"; 
                end
            `IX_WRITE_CAPABILITIES: begin
                instruction_name[0] <= "W"; 
                instruction_name[1] <= "R"; 
                instruction_name[2] <= " "; 
                instruction_name[3] <= "C"; 
                instruction_name[4] <= "A"; 
                instruction_name[5] <= "P"; 
                end
            `IX_READ_PERF, `IX_READ_PERFS: begin
                instruction_name[0] <= "R"; 
                instruction_name[1] <= "D"; 
                instruction_name[2] <= " "; 
                instruction_name[3] <= "P"; 
                instruction_name[4] <= "E"; 
                instruction_name[5] <= "R"; 
                end
            `IX_READ_SYS: begin
                instruction_name[0] <= "R"; 
                instruction_name[1] <= "D"; 
                instruction_name[2] <= " "; 
                instruction_name[3] <= "S"; 
                instruction_name[4] <= "Y"; 
                instruction_name[5] <= "S"; 
                end
            `IX_WRITE_SYS: begin
                instruction_name[0] <= "W"; 
                instruction_name[1] <= "R"; 
                instruction_name[2] <= " "; 
                instruction_name[3] <= "S"; 
                instruction_name[4] <= "Y"; 
                instruction_name[5] <= "S"; 
                end
            `IX_MOVE_BITS1, `IX_MOVE_BITS2: begin
                instruction_name[0] <= "M"; 
                instruction_name[1] <= "O"; 
                instruction_name[2] <= "V"; 
                instruction_name[3] <= "b"; 
                end
            `IX_SHIFT32: begin
                instruction_name[0] <= "<"; 
                instruction_name[1] <= "<"; 
                instruction_name[2] <= "3"; 
                instruction_name[3] <= "2"; 
                end
            `IX_INSERT_HI: begin
                instruction_name[0] <= "I"; 
                instruction_name[1] <= "N"; 
                instruction_name[2] <= "S"; 
                instruction_name[3] <= "h"; 
                instruction_name[4] <= "i"; 
                end
            `IX_ADDRESS: begin
                instruction_name[0] <= "A"; 
                instruction_name[1] <= "D"; 
                instruction_name[2] <= "D"; 
                instruction_name[3] <= "R"; 
                end
            `IX_TRUTH_TAB3: begin
                instruction_name[0] <= "T"; 
                instruction_name[1] <= "T"; 
                instruction_name[2] <= "A"; 
                instruction_name[3] <= "B"; 
                instruction_name[4] <= "3"; 
                end
            `IX_INPUT: begin
                instruction_name[0] <= "I"; 
                instruction_name[1] <= "N"; 
                instruction_name[2] <= "P"; 
                instruction_name[3] <= "U"; 
                instruction_name[4] <= "T"; 
                end
            `IX_OUTPUT: begin
                instruction_name[0] <= "O"; 
                instruction_name[1] <= "U"; 
                instruction_name[2] <= "T"; 
                instruction_name[3] <= "P"; 
                instruction_name[4] <= "U"; 
                instruction_name[5] <= "T"; 
                end                
                
            default: begin
                // unknown instruction
                instruction_name[0] <= "?"; 
                instruction_name[1] <= "?"; 
                instruction_name[2] <= "?"; 
                end
            endcase
        end
    end
end

endmodule
