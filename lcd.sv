//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2020-06-22
// Last modified:  2020-06-29
// Module Name:    decoder
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Driver for LCD displays
// Two LCD displays with each 4 lines x 20 characters
//////////////////////////////////////////////////////////////////////////////////

`include "defines.vh"

module lcd 
  #(parameter numrows = 8,               // number of lines of combined displays (2 - 8)
    parameter numcolumns = 20,           // number of characters per line
    parameter rows_per_display = 4)      // number of rows per display unit
 (input       clock,                     // system clock 100 MHz
  input       reset,                     // reset and clear
  input [4:0] x,                         // column number (0 = left)
  input [2:0] y,                         // row number (0 = top)
  input [7:0] text[0:numcolumns-1],      // text for one line
  input [4:0] text_length,               // length of text
  input       start,                     // start writing
  input       eol,                       // pad with spaces until end of line
  output reg  lcd_rs,                    // LCD RS pin
	output reg  [1:0] lcd_e,               // enable pins for two LCD displays
	output reg  [3:0] lcd_data,            // LCD data, 4 bit bus
	output reg  ready                      // finished writing. ready for next line
);

localparam count_bits = 14;              // number of bits in clock divider counter
localparam count_max = (2**count_bits)-1;// maximum count

logic [7:0] rowaddress;                  // command for setting row address
reg [count_bits-1:0] counter = 0;        // clock divider
reg [7:0] delay;                         // delay counter
reg [3:0] state = 0;                     // state machine for initialization
                                         // 0  -  9: initialization sequence
                                         // 10 - 11: set x,y position
                                         // 12 - 13: write characters
                                         // 15:      finished
reg [7:0] text_buffer [0:numcolumns-1];  // copy of input text
reg [4:0] column;                        // text column
reg [2:0] row;                           // text row
reg [4:0] text_count;                    // count down characters in text
reg       eol_save;                      // copy of eol

/* initialization sequence:
The display can receive data in 4-bit or 8-bit mode. We are using 4-bit mode,
sending 4 bits at a time, with only the upper four bits connected.
First, we send 8'H3x three times to get into 8-bit mode. Then 8'H2x to get
into 4-bit mode. The remaining numbers are 8-bit pairs:
8'H28: multi-line mode (the first needs a long delay)
8'H01: reset (needs long delay)
8'H0C: display on, no cursor, no blink
//8'H06 forward direction  
*/
reg [3:0] initialization_sequence [10] = {3, 3, 3, 2, 2, 8, 0, 1, 0, 12 };

always_comb begin
    // command to set row address
    if (rows_per_display == 4) begin
        case (row[1:0]) // 4 lines per display
        0: rowaddress = 8'H80 + column;
        1: rowaddress = 8'HC0 + column;
        2: rowaddress = 8'H80 + numcolumns + column;
        3: rowaddress = 8'HC0 + numcolumns + column;    
        endcase
    end else begin
        case (row[0])   // 2 lines per display
        0: rowaddress = 8'H80 + column;
        1: rowaddress = 8'HC0 + column;
        endcase    
    end
end

always_ff @(posedge clock) begin
    lcd_e <= 0;
    
    if (reset) begin            
        // reset
        counter <= 0;
        delay <= 8'H80;
        state <= 0;
        
    end else if (start && state == 15) begin
        // write command received
        text_buffer <= text;
        column <= x;
        row <= y;
        text_count <= text_length;
        eol_save <= eol;
        counter <= 0;
        state <= 10;
            
    end else begin        
        counter <= counter + 1; // 2**count_bits / 100MHz = 160 µs        
        if (state < 10) begin
        
            // initialization sequence
            lcd_rs <= 0;
            if (delay > 0) begin
                if (counter == count_max) delay <= delay - 1;
            end else begin
                lcd_data <= initialization_sequence[state];
                lcd_e[0] <= counter[count_bits-1:count_bits-2] == 2'b01; // generate pulse for display unit 0
                lcd_e[1] <= counter[count_bits-1:count_bits-2] == 2'b01; // generate pulse for display unit 1
                if (counter == count_max) begin
                    if (state == 9) state <= 15; // finished
                    else state <= state + 1;     // next state
                    delay <= 8'H10;
                end
            end
            
        end else if (state < 12) begin
        
            // set (x,y) position
            lcd_rs <= 0;
            if (delay > 0) begin
                if (counter == count_max) delay <= delay - 1;
            end else begin
                lcd_data <= ~state[0] ? rowaddress[7:4] : rowaddress[3:0];
                if (row < rows_per_display)
                     lcd_e[0] <= counter[count_bits-1:count_bits-2] == 2'b01; // generate pulse
                else lcd_e[1] <= counter[count_bits-1:count_bits-2] == 2'b01; // generate pulse
                if (counter == count_max) begin
                    state <= state + 1;
                    delay <= 8'H10;
                end
            end
            
        end else if (state < 15) begin

            // write characters
            lcd_rs <= 1;
            if (delay > 0) begin
                if (counter == count_max) delay <= delay - 1;
            end else begin
                if (text_count > 0) begin
                    // write character
                    lcd_data <= ~state[0] ? text_buffer[0][7:4] : text_buffer[0][3:0];
                    if (row < rows_per_display)
                         lcd_e[0] <= counter[count_bits-1:count_bits-2] == 2'b01; // generate pulse
                    else lcd_e[1] <= counter[count_bits-1:count_bits-2] == 2'b01; // generate pulse
                end else if (eol_save) begin
                    lcd_data <= ~state[0] ? 2 : 0;                                // write space
                    if (row < rows_per_display)
                         lcd_e[0] <= counter[count_bits-1:count_bits-2] == 2'b01; // generate pulse
                    else lcd_e[1] <= counter[count_bits-1:count_bits-2] == 2'b01; // generate pulse
                end                        
                
                if (counter == count_max) begin
                    if (state[0]) begin
                        column <= column + 1;                                     // count up column index
                        if (text_count != 0) text_count <= text_count - 1;        // count down number of characters
                        for (int i = 0; i < numcolumns-1; i++) begin
                            text_buffer[i] <= text_buffer[i+1];                   // shift down to get next character
                        end                        
                    end                
                    if (state[0] && (column == numcolumns-1 || (text_count == 0 && !eol_save))) begin
                        state <= 15;                                              // finished                
                    end else begin
                        state[0] <= ~state[0];
                    end
                    // delay <= 8'H01;
                end
            end
        end else begin 
            // state = 15. finished
            lcd_e <= 0;
        end
    end
    if (state == 15) ready <= 1;
    else ready <= 0;
       
end 


endmodule
