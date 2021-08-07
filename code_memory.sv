//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:       2020-05-05
// Last modified:     2021-08-02
// Module Name:       code_cache
// Project Name:      ForwardCom soft core
// Target Devices:    Artix 7
// Tool Versions:     Vivado v. 2020.1
// License:           CERN-OHL-W v. 2 or later
// Description:       on-chip code memory or code cache
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"

// It takes two clock cycles to fetch data from on-chip ram,
// Attempts to fetch in one cycle, using negedge or latch failed for timing reasons


// code memory, 1024*64 bits, 
module code_memory (
    input clock,                                 // clock
    input clock_enable,                          // clock enable. Used when single-stepping
    input read_enable,                           // read enable when fetching code
    input [7:0] write_enable,                    // write enable for each byte separately when writing code. must be 0x0F or 0xF0 or 0xFF 
    input [`COMMON_ADDR_WIDTH-1:0] write_addr_in,// Address lines when writing to code memory
    input [63:0] write_data_in,                  // Data lines when writing to code memory
    input [`CODE_ADDR_WIDTH-2:0] read_addr_in,   // Address for reading from code memory
    output reg [`CODE_DATA_WIDTH-1:0] data_out,  // Data out
    
    // outputs for debugger:
    output reg [31:0] debug_out           // debug information    
);

// code ram
reg [`CODE_DATA_WIDTH-1:0] ram[0:(2**(`CODE_ADDR_WIDTH-1)-1)];
// (attempt to split this into 32-bit lines failed to implement as ram block)

logic [`COMMON_ADDR_WIDTH-4:0] write_address_hi; 
//logic [`DATA_ADDR_WIDTH-4:0] write_address_hi; 
//logic [2:0] address_lo; // not used 
logic write_address_valid;

always_comb begin
//    write_address_hi = write_addr_in[`COMMON_ADDR_WIDTH-1:3] - {1'b1,`CODE_ADDR_START'b0}; // index to 64-bit lines
    write_address_hi = write_addr_in[`COMMON_ADDR_WIDTH-1:3] - {1'b1,{(`CODE_ADDR_START-3){1'b0}}}; // index to 64-bit lines
    write_address_valid = write_addr_in[`COMMON_ADDR_WIDTH-1:`CODE_ADDR_START] != 0;       // code address space
end 

/*
Calculation of loader address:
Code memory starts at address 2**CODE_ADDR_START = 32kB = 0x8000
Code memory size = 2**(CODE_ADDR_WIDTH+2) = 64kB = 0x10000
Code memory end = code memory start + code memory size = 0x18000
Max loader size = 2kB = 0x800 bytes
Loader start address = code memory end - max loader size
Each line in code ram is CODE_DATA_WIDTH = 64 bits = 8 bytes
Loader start line = (code memory size - max loader size) / line size
*/
parameter max_loader_size   = `MAX_LOADER_SIZE << 2;   // loader size in bytes
parameter code_memory_start = 2**`CODE_ADDR_START;
parameter code_memory_size  = 2**(`CODE_ADDR_WIDTH+2);
parameter code_memory_end   = code_memory_start + code_memory_size;
parameter loader_start_address = code_memory_end - max_loader_size;
parameter loader_start_relative = code_memory_size - max_loader_size;
parameter loader_start_line = loader_start_relative / (`CODE_DATA_WIDTH >> 3);

generate if (`LOADER_FILE != "") 
    initial begin
        // insert loader code
        $readmemh(`LOADER_FILE, ram, loader_start_line);
    end
endgenerate


// code ram read and write process
always_ff @(posedge clock) if (clock_enable) begin

    // Write data to code RAM when loading program code
    if (write_address_valid) begin  // write address is in code section
        if (write_enable[0]) begin
            ram[write_address_hi][31:0] <= write_data_in[31:0];
        end
        if (write_enable[4]) begin
            ram[write_address_hi][63:32] <= write_data_in[63:32];
        end            
    end 
    
    // Read from code ram when executing 
    if (read_enable) begin
        data_out <= ram[read_addr_in];
    end
    
    // Output for debugger
    debug_out[23:0] <= write_address_hi;
    debug_out[28] <= write_address_valid;
    
end

endmodule
