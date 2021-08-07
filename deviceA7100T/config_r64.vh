//////////////////////////////////////////////////////////////////////////////////
// Engineer:       Agner Fog
// 
// Create Date:    2020-06-06
// Last modified:  2021-08-06
// Module Name:    config_r64.vh
// Project Name:   ForwardCom soft core model A
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Configuration parameters 
//
// Configuration for 64 bit registers, 32kB data RAM, 64 kB code RAM
//
//////////////////////////////////////////////////////////////////////////////////

`define NUM_VECTOR_UNITS       0       // number of 64-bit vector units or lanes

// Decide if we have 64 bits support. We can use less resources and have higher speed with the 32 bit version. 
// If 32 bits: General purpose registers are 32 bits. Temporary operand buffers are 32 bits.
// Result buses are 32 bits. Results will be 32 bits, even for 64 bit instructions. 
// The data write buses to data cache and code cache are still 64 bits, using any part of the bus for smaller operand sizes.
// If 64 bits: General purpose registers are 64 bits. 64 bit operand size is supported.

// Uncomment this to support 64-bit operand type:
`define SUPPORT_64BIT

`ifdef SUPPORT_64BIT
    `define RB                    64   // size of general purpose registers, 64 bits
    `define RB1                   63   // index of most significant bit
`else
    `define RB                    32   // size of general purpose registers, 32 bits
    `define RB1                   31   // index of most significant bit
`endif 

// number of bits used in mask registers must be TAG_WIDTH < MASKSZ <= RB
`define MASKSZ                  16
//`define MASKSZ                    32
//`define MASKSZ                 `RB


// Clock frequency
// Xilinx-specific:
// To change the clock frequency, click on the clock_generator source to open the
// Vivado Clocking Wizard and set the requested output frequency.
// Use the timing summary to check if the design can work with this frequency.
// The frequency defined below must match the frequency set in the clocking wizard: 
//`define CLOCK_FREQUENCY   68000000   // max clock frequency for 32-bit version
`define CLOCK_FREQUENCY    58000000   // max clock frequency for 64-bit version


// Serial input/output BUAD rate. 8 data bits, no parity, 1 stop bit 
//`define BAUD_RATE      19200
`define BAUD_RATE        57600
//`define BAUD_RATE      115200

// serial input  buffer size is 2**IN_BUFFER_SIZE_LOG2 bytes
// serial output buffer size is 2**OUT_BUFFER_SIZE_LOG2 bytes
`define IN_BUFFER_SIZE_LOG2    10      // 1 kbyte
`define OUT_BUFFER_SIZE_LOG2   11      // 2 kbytes

// initial code in 64-bit lines. remember to put the second 32-bit word to the left:
`define LOADER_FILE "loader.mem"       // filename of hex file of machine code for loader
`define MAX_LOADER_SIZE 32'H200        // >= size of loader code, in 32-bit words. Must be even
// Loader entry address is the end of code memory - MAX_LOADER_SIZE
// Restart address is the same address + 1

// code ram address lines. Each line has one 32-bit word = 4 bytes
// code ram size = 2**(CODE_ADDR_WIDTH+2)
//`define CODE_ADDR_WIDTH 13  // 32 kB
`define CODE_ADDR_WIDTH 14  // 64 kB
//`define CODE_ADDR_WIDTH 15  // 128 kB

// data ram address lines. Each line has 1 byte. 
// data ram size = (2**DATA_ADDR_WIDTH)
`define DATA_ADDR_WIDTH 15   // 32 kB

// total address lines for code and data combined, used when writing code. 
// Total address space = (2**COMMON_ADDR_WIDTH) bytes
`define COMMON_ADDR_WIDTH ((`CODE_ADDR_WIDTH+2>`DATA_ADDR_WIDTH) ? `CODE_ADDR_WIDTH+3 : `DATA_ADDR_WIDTH+1)

// The code address space must start immediately after the data address space if IP-addressed data are used without load-time relocation:  
`define CODE_ADDR_START `DATA_ADDR_WIDTH   // code write address starts at 2**`CODE_ADDR_START = end of data address space

// code ram bus width
`define CODE_DATA_WIDTH 64

// The number of entries in the call stack size is 2**CALL_STACK_POINTER_BITS - 1
`define CALL_STACK_POINTER_BITS  10

// number of system registers that behave as g.p. registers (renamed in flight)
`define NUM_SYS_REGISTERS    3

// number of bits in instruction ID tag. 
// The maximum number of instruction tags in flight is 2**TAG_WIDTH - 1  
`define TAG_WIDTH  5

// number of error types distinguished
`define N_ERROR_TYPES  6

// Input/output port numbers
`define INPORT_RS232            8      // input port for RS232 serial input
`define INPORT_RS232_STATUS     9      // input port to read status of RS232 serial input
`define OUTPORT_RS232          10      // output port for RS232 serial output
`define OUTPORT_RS232_STATUS   11      // output port for RS232 serial output status
 
