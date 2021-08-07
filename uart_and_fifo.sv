//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog 
// 
// Create date:    2020-11-01
// Last modified:  2021-07-02
// Module name:    uart_and_fifo
// Project name:   ForwardCom soft core
// Tool versions:  Vivado 2020.1 
// License:        CERN-OHL-W v. 2 or later
// Description:    UART: RS232 serial interface
// 8 data bits, 1 stop bit, no parity
// Description:    fifo_buffer: First-in-first-out byte queue.
//
//////////////////////////////////////////////////////////////////////////////////

// CLOCK_FREQUENCY and BAUD_RATE defined in defines.vh:
`include "defines.vh"

// UART receiver
module UART_RX (
    input            reset,                      // clear buffer, reset everything 
    input            clock,                      // clock at `CLOCK_RATE
    input            rx_in,                      // RX input
    output reg       receive_complete_out,       // byte received. Will be high for 1 clock cycle after the middle of the stop bit
    output reg       error_out,                  // transmission error. Remains high until reset in case of error
    output reg [7:0] byte_out                    // byte output
);
   
// clock count per bit
localparam CLKS_PER_BIT = `CLOCK_FREQUENCY / `BAUD_RATE;
 
// state names 
localparam STATE_IDLE      = 4'b0000;            // wait for start bit
localparam STATE_START_BIT = 4'b0001;            // start bit detected
localparam STATE_DATA_0    = 4'b1000;            // read first data bit
localparam STATE_DATA_7    = 4'b1111;            // read last data bit
localparam STATE_STOP_BIT  = 4'b0010;            // read stop bit

reg [$clog2(CLKS_PER_BIT)-1:0] clock_counter;    // clock counter for length of one bit
reg [3:0] state;  // state


// state machine for UART receiver
always_ff @(posedge clock) begin

    if (reset) begin
        // reset everything
        state <= STATE_IDLE;
        receive_complete_out <= 0;
        error_out <= 0;
        clock_counter <= 0;
        byte_out <= 0;
                
    end else if (state == STATE_IDLE) begin
        // wait for start bit
        receive_complete_out <= 0;
        clock_counter <= 0;
        if (rx_in == 0) begin                    // Start bit detected
            state <= STATE_START_BIT;
        end
        
    end else if (state == STATE_START_BIT) begin
        // start bit detected. wait until middle of start bit
        if (clock_counter == CLKS_PER_BIT / 2) begin // middle of start bit
            if (rx_in == 0) begin
                clock_counter <= 0;              // reset counter to the middle of the start bit
                state     <= STATE_DATA_0;
            end else begin
                error_out <= 1;                  // error. start bit shorter than a half period. possibly wrong BAUD rate
                state <= STATE_IDLE;
            end
        end else begin
            clock_counter <= clock_counter + 1;  // count time until next bit
        end

    end else if (state[3]) begin                 // this covers STATE_DATA_0 ... STATE_DATA_7
        // read eight data bits 
    
        if (clock_counter < CLKS_PER_BIT-1) begin
            clock_counter <= clock_counter + 1;  // count time until next bit
        end else begin                           // middle of data bit. sample bit and go to next state
            clock_counter        <= 0;
            byte_out[state[2:0]] <= rx_in;       // save data bit
            if (state == STATE_DATA_7) state <= STATE_STOP_BIT; // next state is stop bit
            else state <= state + 1;                            // next data bit
        end
        
    end else if (state == STATE_STOP_BIT) begin          
        // expecting stop bit
        if (clock_counter < CLKS_PER_BIT-1) begin
            clock_counter <= clock_counter + 1;  // count time until stop bit
        end else begin                           // middle of stop bit
            if (rx_in == 0) begin                // error: stop bit missing
                error_out <= 1;
                state <= STATE_IDLE;
            end else begin
                receive_complete_out <= 1;       // byte received successfully
                clock_counter <= 0;
                // We are in the middle of the stop bit.
                // Go to state IDLE while waiting for a possible next start bit.
                // This is expected to last a half period
                state <= STATE_IDLE;
            end        
        end 
    end else begin
        // Error. undefined state
        error_out <= 1;
        state <= STATE_IDLE;    
    end         
end
endmodule // UART_RX


// UART transmitter
module UART_TX (
   input       reset,                            // reset 
   input       clock,                            // clock at `CLOCK_RATE
   input       start_in,                         // command to send one byte
   input [7:0] byte_in,                          // byte input
   output reg  active_out,                       // is busy
   output reg  tx_out,                           // TX output
   output reg  done_out                          // will be high for one clock cycle shortly before the end of the stop bit
   );                                            // You may use done_out as a signal to prepare the next byte
 
// clock count per bit
localparam CLKS_PER_BIT = `CLOCK_FREQUENCY / `BAUD_RATE;

// state names 
localparam STATE_IDLE      = 4'b0000;            // wait for start bit
localparam STATE_START_BIT = 4'b0001;            // start bit detected
localparam STATE_DATA_0    = 4'b1000;            // read first data bit
localparam STATE_DATA_7    = 4'b1111;            // read last data bit
localparam STATE_STOP_BIT  = 4'b0010;            // read stop bit

reg [3:0] state;                                 // state
reg [$clog2(CLKS_PER_BIT)-1:0] clock_counter;    // clock counter for length of one bit
reg [7:0] byte_data;                             // copy of byte to transmit


// state machine
always_ff @(posedge clock) begin
    if (reset) begin
        // reset everything
        state <= STATE_IDLE;
        clock_counter <= 0;
        active_out    <= 0;
        done_out      <= 0;
        tx_out        <= 1;                      // output must be high when idle
        
    end else if (state == STATE_IDLE) begin
        clock_counter <= 0;
        done_out      <= 0;
        tx_out        <= 1;                      // output must be high when idle
        if (start_in) begin                      // start sending a byte
            active_out <= 1;
            byte_data  <= byte_in;               // copy input byte
            state <= STATE_START_BIT;
        end

    end else if (state == STATE_START_BIT) begin
        // start bit must be 0
        tx_out <= 0;
        
        // Wait for start bit to finish
        if (clock_counter < CLKS_PER_BIT-1) begin
            clock_counter <= clock_counter + 1;
        end else begin
            clock_counter <= 0;
            state <= STATE_DATA_0;               // go to first data bit
        end
        
    end else if (state[3]) begin                 // this covers STATE_DATA_0 ... STATE_DATA_7
        // write eight data bits
        tx_out <= byte_data[state[2:0]];         // send one data bit
        
        // Wait for data bit to finish
        if (clock_counter < CLKS_PER_BIT-1) begin
            clock_counter <= clock_counter + 1;
        end else begin
            clock_counter <= 0;
            if (state == STATE_DATA_7) state <= STATE_STOP_BIT; // next bit is stop bit
            else state <= state + 1;                            // next bit is data bit
        end 

    end else if (state == STATE_STOP_BIT) begin
        // send stop bit
        tx_out <= 1;                             // stop bit must be 1
        
        // send request for next byte shortly before finished with this byte
        if (clock_counter == CLKS_PER_BIT-4) begin
            done_out <= 1;                       // set done_out high for one clock cycle to request next byte from buffer
        end else begin
            done_out <= 0;
        end
            
        // Wait for stop bit to finish
        if (clock_counter < CLKS_PER_BIT-1) begin
            clock_counter <= clock_counter + 1;
        end else begin
            clock_counter <= 0;
            begin
                active_out <= 0;
                state      <= STATE_IDLE;        // wait at least one clock for next start_in signal
            end
        end
        
    end else begin  
        // illegal state. reset
        state <= STATE_IDLE;
        clock_counter <= 0;
        active_out <= 0;
        done_out <= 0;
        tx_out   <= 1;     
    end 
end


endmodule


/******************************************************************************
* First-in-first-out byte queue.
*
* This queue is implemented as a circular buffer. 
* The size can be any power of 2. 
* It may be implemented as distributed RAM or block RAM if the size is large. 
* (Vivado does this automatically)
* It is possible to read and write simultaneously as long as the queue is not 
* empty. It is not possible to pass a byte directly from input to output without
* a delay of two clocks if the buffer is empty.
* The input, byte_in, is placed at the tail of the queue at the rising edge of clock.
* The output, byte_out, is prefetched so that it is ready to read before the
* clock edge. The read_next input signal will remove one byte from the head of 
* the queue and put the next byte into byte_out. 
* The data_ready_out output tells if it is possible to read a byte
******************************************************************************/

module fifo_buffer
#(parameter size_log2 = 10)                      // buffer size = 2**size_log2 bytes
(
    input            reset,                      // clear buffer and reset error condition 
    input            reset_error,                // reset error condition 
    input            clock,                      // clock at `CLOCK_RATE
    input            read_next,                  // read next byte from buffer
    input            write,                      // write one byte to buffer
    input  [7:0]     byte_in,                    // serial byte input
    output reg [7:0] byte_out,                   // serial byte output prefetched
    output reg       data_ready_out,             // the buffer contains at least one byte
    output reg       overflow,                   // attempt to write to full buffer
    output reg       underflow,                  // attempt to read from empty buffer
    output reg [size_log2-1:0] num               // number of bytes currently in buffer
);

reg [7:0] buffer[0 : (2**size_log2)-1];          // circular buffer
reg [size_log2-1:0] head;                        // pointer to head position where bytes are extracted
reg [size_log2-1:0] tail;                        // pointer to tail position where bytes are inserted

logic [size_log2-1:0] head_plus_1;               // (head + 1) modulo 2**(size_log2)


always_ff @(posedge clock) begin

    if (reset) begin
        // clear buffer, reset everything
        head <= 0;
        tail <= 0;
        byte_out <= 0;
        num <= 0;
        data_ready_out <= 0;
        overflow <= 0;
        underflow <= 0;
    end else if (reset_error) begin
        // reset error flags
        overflow <= 0;
        underflow <= 0;
    end else begin
        if (write) begin
            // insert a byte in buffer
            if (&num) begin
                // buffer is full
                overflow <= 1;        
            end else begin
                // buffer is not full
                buffer[tail] <= byte_in;         // insert at tail position

                // advance tail
                tail <= tail + 1;                // this will wrap around because size is a power of 2
                // count bytes in buffer            
                if (!read_next) begin
                    num <= num + 1;
                end
            end
        end
        
        // make output ready
        if (num == 0 || read_next && num == 1) begin
            byte_out <= 0;
            data_ready_out <= 0;
        end else if (read_next) begin
            byte_out <= buffer[head_plus_1];     // read byte and make next byte ready from head position            
            data_ready_out <= 1;
        end else begin
            byte_out <= buffer[head];            // make byte read ready from head position
            data_ready_out <= 1;                    
        end
        
        if (read_next) begin
            // read a byte from buffer
            if (~data_ready_out) begin           // reading from empty buffer
                underflow <= 1;
            end else begin
                // advance head
                head <= head_plus_1;             // this will wrap around because size is a power of 2
                // count bytes in buffer            
                if (!write) begin
                    num <= num - 1;
                end
            end
        end
    end
end


always_comb begin
    head_plus_1 = head + 1;                      // (head + 1) with size_log2 bits
end

endmodule
