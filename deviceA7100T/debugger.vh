//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog 
// 
// Create date:   2020-05-25
// Last modified: 2021-08-03
// Module name:   debugger
// Project name:  ForwardCom soft core
// Tool versions: Vivado 2020.1 
// License: CERN-OHL-W
// Description: Debug feature giving access to any signal in the pipeline.
// The signal to show is selected with input switches and shown on 7-segment displays
//////////////////////////////////////////////////////////////////////////////////

// debug output on 7-segment display
// switch 8:0: select what to show on display, according to the cases below.

logic [8:0] debug_out_select ;       // select what to show on debug display
reg [7:0]   enable_digits;           // enable each digit
reg [31:0]  debugOut;                // output to debug display
reg [26:0]  clock_counter = 0;       // divide clock by 100E6
reg [15:0]  clock_1 = 0;             // second counter for testing clock frequency

always_ff @(posedge clock) begin

    // divide clock for testing
    if (clock_counter == 100000000) begin
        clock_counter <= 0;
        clock_1 <= clock_1 + 1;
    end else begin
        clock_counter <= clock_counter + 1;
    end
    
    enable_digits <= 8'b11111111;
    color_led16 <= 0;
    
/*  List the signals you want to be available on the display. You may change this list.
    If you want to see local signals within a module, then the best way is as follows:
    Make one or more debug output registers in the module. Local variables that are not 
    register variables are clocked out to the debug output register. Local variables that
    are already registered should be assigned to the debug output rather than be clocked  
    out in order to prevent an extra clock cycle delay. See fetch.sv for an example.
    All debug signals should apply to the same clock cycle in order to prevent confusion.
    You may comment out some signals in order to save resources.
*/      
    debug_out_select <= {switch8,switch7,switch6,switch5,switch4,switch3,switch2,switch1,switch0};
    case (debug_out_select)    
    
        // fetch unit
        8'b00000000: debugOut <= fetch_instruction[31:0];
        8'b00000001: debugOut <= fetch_instruction[63:32];
        8'b00000010: debugOut <= fetch_instruction[95:64];
        8'b00000011: debugOut <= fetch_instruction_pointer;
        8'b00000100: debugOut <= {fetch_read_enable,{(27-`CODE_ADDR_WIDTH){1'b0}},fetch_read_addr,1'b0}; // fetch_read_addr = half value
        8'b00000101: debugOut <= code_memory_data[31:0];
        8'b00000110: debugOut <= code_memory_data[63:32];
        8'b00000111: debugOut <= {fetch_valid,2'b0,fetch_jump};
        //8'b00001111: debugOut <= call_stack_pop_data;
        8'b00001000: debugOut <= fetch_debug1; 
        
        // decoder
        //8'b00010000: debugOut <= decoder_instruction[31:0];
        //8'b00010001: debugOut <= decoder_instruction[63:32];
        8'b00010010: debugOut <= decoder_instruction_pointer;
        8'b00010100: debugOut <= {decoder_num_operands, 3'b0,decoder_mask_options, 2'b0,decoder_rd_status, 2'b0,decoder_ru_status, 1'b0,decoder_rt_status, 1'b0,decoder_rs_status};
        8'b00010101: debugOut <= {decoder_index_limit,  2'b0,decoder_scale_factor,  2'b0,decoder_offset_field,  2'b0,decoder_result_type};
        8'b00010110: debugOut <= {decoder_num_operands,  2'b0,decoder_format,  2'b0,decoder_category};
        8'b00011000: debugOut <= {decoder_read,decoder_tag_write, 3'b0,decoder_tag_val, 2'b0,decoder_tag_a};
        8'b00011110: debugOut <= {  2'b0,decoder_result_type};
        8'b00011111: debugOut <= decoder_debug1;        
        
        // register read stage
        //8'b00100000: debugOut <= registerread_instruction[31:0];
        8'b00100010: debugOut <= registerread_instruction_pointer;
        8'b00100011: debugOut <= {registerread_num_operands, 2'b0,registerread_rd_status, 2'b0,registerread_ru_status, 1'b0,registerread_rt_status, 1'b0,registerread_rs_status};
        8'b00100100: debugOut <= registerread_fallback_use; 
        8'b00100110: debugOut <= {registerread_stall_predict, 3'b0,registerread_valid};
        8'b00101000: debugOut <= {registerread_rd_val[`RB], 3'b0,registerread_rd_val[27:0]};
        8'b00101001: debugOut <= {registerread_rs_val[`RB], 3'b0,registerread_rs_val[27:0]};
        8'b00101010: debugOut <= {registerread_rt_val[`RB], 3'b0,registerread_rt_val[27:0]};
        8'b00101011: debugOut <= {registerread_ru_val[`RB], 3'b0,registerread_ru_val[27:0]};
        8'b00101100: debugOut <= {registerread_regmask_val[`MASKSZ],3'b0,registerread_rd_val[`RB],3'b0,registerread_rs_val[`RB],3'b0,registerread_rt_val[`RB]};
        8'b00101110: debugOut <= registerread_tag_val;
        
        // address generator        
        //8'b00110000: debugOut <= addrgen_instruction[31:0];
        8'b00110001: debugOut <= addrgen_read_write_address;
        8'b00110011: debugOut <= addrgen_instruction_pointer;
        8'b00110100: debugOut <= {addrgen_stall_next, 3'b0,addrgen_valid};
        8'b00110101: debugOut <= addrgen_result_type;        
        8'b00110110: debugOut <= addrgen_write_enable;
        8'b00110111: debugOut <= addrgen_write_data;
        8'b00111000: debugOut <= {addrgen_operand1[`RB], 3'b0,addrgen_operand1[27:0]};
        8'b00111001: debugOut <= {addrgen_operand2[`RB], 3'b0,addrgen_operand2[27:0]};
        8'b00111010: debugOut <= {addrgen_operand3[`RB], 3'b0,addrgen_operand3[27:0]};
        8'b00111011: debugOut <= addrgen_tag_val;
        8'b00111100: debugOut <= {addrgen_regmask_val[`MASKSZ], 12'b0,addrgen_regmask_val[15:0]};
        8'b00111101: debugOut <= addrgen_debug1;
        8'b00111110: debugOut <= addrgen_debug2;
        8'b00111111: debugOut <= addrgen_debug3;
        
        // dataread stage
        //8'b01000000: debugOut <= dataread_instruction[31:0];
        8'b01000010: debugOut <= dataread_instruction_pointer;
        8'b01000011: debugOut <= {dataread_ot,    dataread_exe_unit, 2'b0,dataread_format, 2'b0,dataread_num_operands, dataread_vector,1'b0,dataread_category};
        8'b01000100: debugOut <= {2'b0,dataread_option_bits,    2'b0,dataread_opj, 1'b0,dataread_opx};
        8'b01000101: debugOut <= {dataread_mask_alternative,dataread_regmask_used};
        8'b01000110: debugOut <= {2'b0,dataread_num_operands, 1'b0,dataread_opr3_used,dataread_opr2_used,dataread_opr1_used};
        8'b01000111: debugOut <= {dataread_im2_bits,  10'b0,dataread_option_bits};        
        8'b01001000: debugOut <= {dataread_operand1[`RB], 3'b0,dataread_operand1[27:0]};
        8'b01001001: debugOut <= {dataread_operand2[`RB], 3'b0,dataread_operand2[27:0]};
        8'b01001010: debugOut <= {dataread_operand3[`RB], 3'b0,dataread_operand3[27:0]};
        8'b01001011: debugOut <= {dataread_mask_val[`MASKSZ], 12'b0,dataread_mask_val[15:0]};
        8'b01001100: debugOut <= {2'b0,dataread_opj,  1'b0,dataread_opx,  2'b0,dataread_instruction[`OP1]};                
        8'b01001101: debugOut <= dataread_tag_val;
        8'b01001110: debugOut <= {dataread_opr3_from_ram,dataread_opr2_from_ram, 2'b0,dataread_result_type};
        8'b01001111: debugOut <= dataread_debug;

        // alu
        8'b01010000: debugOut <= bus1_value[31:0];
        8'b01010001: debugOut <= bus1_register_a;
        8'b01010010: debugOut <= {dataread_opx,  dataread_exe_unit, 2'b0,inout_write_en,alu_write_en};
        8'b01010011: debugOut <= {bus1_tag, 3'b0,inout_tag, 3'b0,alu_tag};
        8'b01010100: debugOut <= {inout_write_en,alu_write_en, 2'b0, inout_error,alu_error, 2'b0,alu_nojump,alu_jump};
        8'b01010101: debugOut <= alu_jump_pointer;        
        8'b01010110: debugOut <= {inout_stall_next,alu_stall_next,  2'b0,inout_stall,alu_stall,  3'b0,dataread_stall_predict,  3'b0,addrgen_stall_next,  3'b0,registerread_stall_predict};
        8'b01010111: debugOut <= {alu_tag,  2'b0,alu_register_a, 3'b0,alu_write_en};
        8'b01011000: debugOut <= alu_result;
        8'b01011001: debugOut <= alu_debug1;
        8'b01011010: debugOut <= alu_debug2;        
        8'b01011011: debugOut <= muldiv_debug1;
        8'b01011100: debugOut <= muldiv_debug2;        
        8'b01011111: debugOut <= inout_debug;        
        
        // pipeline synchronization
        8'b01110000: debugOut <= {inout_stall_next,inout_stall,alu_stall_next,alu_stall, 3'b0,dataread_stall_predict, 3'b0,addrgen_stall_next, 3'b0,registerread_stall_predict};
        8'b01110001: debugOut <= {1'b0,alu_jump,alu_nojump,bus1_write_en, 3'b0,dataread_valid,   1'b0,addrgen_write_enable,addrgen_read_enable,addrgen_valid, 3'b0,registerread_valid, 3'b0,decoder_valid, 3'b0,fetch_valid};
        8'b01110010: debugOut <= {bus1_tag, 10'b0,bus1_register_a};
        8'b01111000: debugOut <= {inout_first_error_address,  2'b0,inout_capab_disable_errors,  4'b0,inout_first_error};
        8'b01111111: debugOut <= clock_1; // Test clock frequency. This will count at CLOCK_FREQUENCY / 10^8        

        // data memory read / write
        8'b10000000: debugOut <= addrgen_read_write_address;
        8'b10000001: debugOut <= {addrgen_read_data_size,3'b0,addrgen_read_enable};
        8'b10000010: debugOut <= data_memory_data;
        8'b10000101: debugOut <= addrgen_write_enable;
        8'b10000110: debugOut <= addrgen_write_data[31:0];
        //8'b10000111: debugOut <= addrgen_write_data[63:32];
        8'b10001000: debugOut <= code_memory_debug;
        
        default: debugOut <= 32'hFFFFFFFF;   
    endcase
    
    color_led16 <= 0;
    if (show_error) begin
        // show error code. this overrides the switch selection
        /* 1: alu_error | muldiv_error | inout_error;                                      // unknown instruction
           2: alu_error_parm | muldiv_error_parm | inout_error_parm | call_stack_overflow; // wrong parameter for instruction
           3: dataread_array_error;                                                        // array index out of bounds
           4: dataread_read_address_error;                                                 // read address violation
           5: dataread_write_address_error;                                                // write address violation
           6: dataread_misaligned_address_error;                                           // misaligned memory address
        */
        debugOut[31:28] <= 4'b1110;  // "E"
        debugOut[27:24] <= inout_first_error;
        debugOut[23:20] <= 0;  
        debugOut[19:0]  <= inout_first_error_address;  
        enable_digits   <= 8'b11011111;
        // blink LED, 25% brightness
        color_led16[0]  <= clock_counter[1:0] == 0 && clock_counter[24]; 
    
    end else if (switch8) begin
        // look into register file
        debug_reada <= debug_out_select[5:0];
        debugOut <= {registerread_debugport[32],3'b0,registerread_debugport[27:0]};        
    end else begin
        debug_reada <= 0;
    end
end

seg7 seg7_inst(clock, debugOut, enable_digits, segment7seg, digit7seg);
