//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2020-06-03
// Last modified:  2021-08-02
// Module Name:    data_cache
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    data memory or data cache for read/write data
//
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"


// read/write data memory or cache, (2**`DATA_ADDR_WIDTH) bytes = 2**16 = 64kB
module data_memory (
    input clock,                                    // clock
    input clock_enable,                             // clock enable. Used when single-stepping
    input [`COMMON_ADDR_WIDTH-1:0] read_write_addr, // Address for reading and writing from/to ram
                                                    // The lower 3 bits of read_write_addr indicate a byte within an 8 bytes line
    input read_enable,                              // read enable
    input [1:0] read_data_size,                     // 8, 16, 32, or 64 bits read
    input [7:0] write_enable,                       // write enable for each byte separately 
    input [63:0] write_data_in,                     // Data in. Always 64 bits. Any part of the write bus can be used when the data size is less than 64 bits
`ifdef DISTRIBUTED_RAM                              // Distributed RAM takes a lot of FPGA resources
    output reg   [`RB1:0] read_data_out             // Data out
`else                                               // Block RAM
    output logic [`RB1:0] read_data_out             // Data out
`endif    
);

// read/write data ram
reg [63:0] dataram [0:(2**(`DATA_ADDR_WIDTH-3))-1]; // 64kB RAM

// split read/write address into double-word index, and byte index
logic [`DATA_ADDR_WIDTH-4:0] address_hi; 
logic [2:0] address_lo; 
logic address_valid;

always_comb begin
    address_hi = read_write_addr[`DATA_ADDR_WIDTH-1:3]; // index to 64-bit lines
    address_lo = read_write_addr[2:0];                  // index to byte within line
    address_valid = read_write_addr[`COMMON_ADDR_WIDTH-1:`DATA_ADDR_WIDTH] == 0; // exclude code addresses
end 


// Data write:
always_ff @(posedge clock) if (clock_enable & address_valid) begin
    // write data to RAM. Each byte enabled separately
    if (write_enable[0]) dataram[address_hi][ 7: 0] <= write_data_in[ 7: 0];
    if (write_enable[1]) dataram[address_hi][15: 8] <= write_data_in[15: 8];
    if (write_enable[2]) dataram[address_hi][23:16] <= write_data_in[23:16];
    if (write_enable[3]) dataram[address_hi][31:24] <= write_data_in[31:24];
    if (write_enable[4]) dataram[address_hi][39:32] <= write_data_in[39:32];
    if (write_enable[5]) dataram[address_hi][47:40] <= write_data_in[47:40];
    if (write_enable[6]) dataram[address_hi][55:48] <= write_data_in[55:48];
    if (write_enable[7]) dataram[address_hi][63:56] <= write_data_in[63:56];
end


// data read. Must have natural alignment

`ifdef DISTRIBUTED_RAM
// The multiplexer comes before the register. This is only possible with distributed RAM.
// Distributed RAM takes a lot of FPGA resources but may allow a slightly higher clock frequency.

always_ff @(posedge clock) if (clock_enable & address_valid & read_enable) begin    

    // Each 64-bit RAM line may be divided into 
    // eight bytes, four 16-bit halfwords, two 32-bit words, or one 64-bit double word:
    case (address_lo)
    0: read_data_out[7:0] <= dataram[address_hi][ 7: 0];
    1: read_data_out[7:0] <= dataram[address_hi][15: 8];
    2: read_data_out[7:0] <= dataram[address_hi][23:16];
    3: read_data_out[7:0] <= dataram[address_hi][31:24];
    4: read_data_out[7:0] <= dataram[address_hi][39:32];
    5: read_data_out[7:0] <= dataram[address_hi][47:40];
    6: read_data_out[7:0] <= dataram[address_hi][55:48];
    7: read_data_out[7:0] <= dataram[address_hi][63:56];
    endcase

    case (address_lo[2:1])
    0: read_data_out[15:8] <= dataram[address_hi][15: 8];
    1: read_data_out[15:8] <= dataram[address_hi][31:24];
    2: read_data_out[15:8] <= dataram[address_hi][47:40];
    3: read_data_out[15:8] <= dataram[address_hi][63:56];
    endcase        

    case (address_lo[2])
    0: read_data_out[31:16] <= dataram[address_hi][31:16];
    1: read_data_out[31:16] <= dataram[address_hi][63:48];
    endcase

    `ifdef SUPPORT_64BIT
        read_data_out[63:32] <= dataram[address_hi][63:32];
    `endif
end

`else  
// block RAM. The multiplexer must come after the register

reg [63:0] read_data;                    // a whole line read from the RAM
reg [2:0]  address_lo2;                  // address_lo saved


always_ff @(posedge clock) if (clock_enable & address_valid & read_enable) begin    
    read_data   <= dataram[address_hi];  // read a 64 bits line from ram
    address_lo2 <= address_lo;           // save low part of address
end

always_comb begin
    // Each 64-bit RAM line may be divided into eight bytes, four 16-bit halfwords,
    // two 32-bit words, or one 64-bit double word.
    // The speed of this multiplexer is very critical because it adds to the delay
    // in the execution unit. We are saving time by not setting unused parts of
    // read_data_out to zero.
    case (address_lo2)
    0: read_data_out[7:0] = read_data[ 7: 0];
    1: read_data_out[7:0] = read_data[15: 8];
    2: read_data_out[7:0] = read_data[23:16];
    3: read_data_out[7:0] = read_data[31:24];
    4: read_data_out[7:0] = read_data[39:32];
    5: read_data_out[7:0] = read_data[47:40];
    6: read_data_out[7:0] = read_data[55:48];
    7: read_data_out[7:0] = read_data[63:56];
    endcase

    case (address_lo2[2:1])
    0: read_data_out[15:8] = read_data[15: 8];
    1: read_data_out[15:8] = read_data[31:24];
    2: read_data_out[15:8] = read_data[47:40];
    3: read_data_out[15:8] = read_data[63:56];
    endcase        

    case (address_lo2[2])
    0: read_data_out[31:16] = read_data[31:16];
    1: read_data_out[31:16] = read_data[63:48];
    endcase

    `ifdef SUPPORT_64BIT
        read_data_out[63:32] = read_data[63:32];
    `endif
end

`endif

endmodule
