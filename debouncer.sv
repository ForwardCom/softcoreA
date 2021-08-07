//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog 
// 
// Create date:    2020-05-03
// Last modified:  2020-12-15
// Module name:    debounce
// Project name:   ForwardCom soft core
// Tool versions:  Vivado 2020.1 
// License:        CERN-OHL-W v. 2 or later
// Description:    Push button debouncer
// 
// Input from one or more pushbuttons is filtered to remove contact noise.
// buttons_out is 1 when buttons_in is stable at 1 over a period.
// buttons_out is 0 when buttons_in is stable at 0 over a period.
// pulse_out is 1 for one clock cycle when the button is pressed
// 
//////////////////////////////////////////////////////////////////////////////////


// pushbutton debouncer
module debounce 
#(parameter num=2)                     // number of buttons to debounce
(
    input clock,                       // system clock 50 - 100 MHz
    input [num-1:0]     buttons_in,    // input from pushbutton 
    output reg[num-1:0] buttons_out,   // debounced output
    output reg[num-1:0] pulse_out      // a single pulse of 1 clock duration when button is pressed
);
reg [19:0] count = 0;                  // clock divider
reg [2:0] shift [num-1:0];             // shift registers
genvar i;
generate
for (i=0; i<num; i++) begin
    always_ff @(posedge clock) begin
        pulse_out[i] <= 0;
        count <= count + 1;                             // divide clock by 2**20
        if (count == 0) begin
            shift[i] <= {shift[i][1:0], buttons_in[i]}; // serial in parallel out shift register
            if (shift[i] == 3'b111) begin               // accept as stable high after 3 consecutive high samples
                if (buttons_out[i] == 0) begin
                    pulse_out[i] <= 1;                  // set pulse_out high only in the first clock cycle after button press is stable
                end
                buttons_out[i] <= 1;                    // button is stable high
            end else if (shift[i] == 3'b000) begin      // accept as stable low after 3 consecutive low samples
                buttons_out[i] <= 0;                    // button is stable low
            end
        end
    end
end
endgenerate 
endmodule

