//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:       2020-05-05
// Last modified:     2021-07-27
// Module Name:       call_stack
// Project Name:      ForwardCom soft core
// Target Devices:    Artix 7
// Tool Versions:     Vivado v. 2020.1
// License:           CERN-OHL-W v. 2 or later
// Description:       on-chip call stack. controls call and return instructions
// 
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"

// call stack, 1024*32 bits, used for function return addresses but not for parameters or local data
// On call instruction: put return address on push_data and set call_e high for one clock cycle.
// On return instruction: the return address is pre-loaded into pop_data for early read. 
// Set return_e high for one clock cycle to make next return address ready.

// It is not allowed to have call_e and return_e in the same clock cycle.
// It is not allowed to have return_e in the first clock cycle after call_e 
// or return_e. This is not a problem in the current design because consecutive
// jump, call, and return instructions are delayed by the access time to the code cache.
// If the design is improved with more efficient branch prediction then it may be 
// necessary to add precautions to prevent a return_e signal in the first clock cycle 
// after another return_e or call_e. 

module call_stack (
    input clock,                                 // clock
    input clock_enable,                          // clock enable. Used when single-stepping
    input reset,                                 // clock enable. Used when single-stepping
    input call_e,                                // Executing call instruction. push_data contains return address
    input return_e,                              // Executing return instruction. return address is available in advance on pop_data
    input  [`CODE_ADDR_WIDTH-1:0] push_data,     // Return address pushed here at call instruction
    output reg [`CODE_ADDR_WIDTH-1:0] pop_data,  // Return address popped here at return instruction
    output reg overflow                          // stack overflow or underflow or error
   );

// site of stack = 2**stack_pointer_bits
parameter integer stack_pointer_bits = `CALL_STACK_POINTER_BITS;

// stack ram, on-chip
reg [`CODE_ADDR_WIDTH-1:0] ram[0:(2**stack_pointer_bits)-1];

// call stack pointer
reg [stack_pointer_bits-1:0] call_stack_pointer = 0;

// call and return operations = push and pop of function return addresses:
always_ff @(posedge clock) if (clock_enable) begin
    overflow <= 0;
    if (reset) begin
        call_stack_pointer <= 0;
        pop_data <= 0;
        overflow <= 0;
        
    end else if (call_e) begin
        if (call_stack_pointer == (2**stack_pointer_bits)-1 || return_e) begin
            overflow <= 1;                          // overflow or other error
        end else begin
            ram[call_stack_pointer] <= push_data;   // push return address on stack
            pop_data <= push_data;                  // make next return address ready
            call_stack_pointer <= call_stack_pointer + 1;        
        end
            
    end else if (return_e) begin
        if (call_stack_pointer == 0) begin
            overflow <= 1;                          // stack underflow
        end else if (call_stack_pointer == 1) begin
            pop_data <= 0;                          // stack empty
            call_stack_pointer <= call_stack_pointer - 1;
        end else begin    
            pop_data <= ram[call_stack_pointer-2];  // make next return address ready
            call_stack_pointer <= call_stack_pointer - 1;
        end
    end
end

endmodule
