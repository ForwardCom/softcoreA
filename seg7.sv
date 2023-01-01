//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2020-05-01
// Last modified:  2021-04-30
// Module Name:    seg7
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Decoder and driver for 8 digit 7 segment display 
//////////////////////////////////////////////////////////////////////////////////


// Driver for 8 digit, 7 segment multiplexed display
module seg7 (
    input clock,                       // system clock
    input [31:0] dispin,               // input, hexadecimal or BCD
    input [7:0] enable,                // enable each digit 
    output reg [7:0] segment7seg,      // segment output, active low
    output reg [7:0] digit7seg         // digit select output, active low
);
reg [14:0]  count = 0; 
logic [2:0] index;
logic [3:0] digit;
logic [7:0] segment;

always_comb begin
    index[2:0] = count[13:11];         // digit index
    digit[3:0] = dispin >> (index*4);  // digit value    
    case(digit)    //   pgfedcba  7-segment bit pattern lookup
        0: segment = 8'b00111111;
        1: segment = 8'b00000110;
        2: segment = 8'b01011011;
        3: segment = 8'b01001111;
        4: segment = 8'b01100110;
        5: segment = 8'b01101101;
        6: segment = 8'b01111101;
        7: segment = 8'b00000111;
        8: segment = 8'b01111111;
        9: segment = 8'b01101111;
     4'hA: segment = 8'b01110111;
     4'hB: segment = 8'b01111100;
     4'hC: segment = 8'b00111001;
     4'hD: segment = 8'b01011110;
     4'hE: segment = 8'b01111001;
     4'hF: segment = 8'b01110001;
    endcase
end

always_ff @(posedge clock) begin
    count <= count + 1;               // clock divider
        
    if (count[10:0] == 0) begin   // scan rate = clock / 2**11
        segment7seg <= ~segment;  // active low output
        /*
        if (enable[index]) 
            digit7seg <= ~(8'b1 << index);  // enable one digit at index
        else
            digit7seg <= 8'b11111111;       // disabled digit
        */
        digit7seg <= ~((8'b1 << index) & enable);  // enable one digit at index
             
    end;
    
end     
endmodule
