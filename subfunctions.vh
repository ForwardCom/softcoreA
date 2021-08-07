//////////////////////////////////////////////////////////////////////////////////
// Engineer: Agner Fog
// 
// Create Date:    2020-06-13
// Last modified:  2021-08-03
// Module Name:    subfunctions
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Subfunctions for calculations:
// bitscan:        find highest set bit
// popcount:       count number of 1-bits
// reversebits:    reverse order of bits
// truth_table_lookup: 3-input truth table
//////////////////////////////////////////////////////////////////////////////////
`include "defines.vh"

// 6-input popcount, fits into 6-input LUT.
function [2:0] popcount6;
    input [5:0] inp;
    integer sum;
    sum = 0;
    for (integer k = 0; k < 6; k ++) begin
        sum += {2'b00, inp[k]};
    end
    return sum;    
endfunction

// 32 input popcount
function [5:0] popcount32;
    input [31:0] inp;
    logic[5:0] sum;
    sum = 0;
    for (integer j = 0; j < 5; j++) begin
        sum += popcount6(inp[(j*6)+:6]);
    end
    sum += popcount6({4'b0,inp[31:30]});
    return sum;    
endfunction

// 64 input popcount
function [6:0] popcount64;
    input [63:0] inp;
    logic[6:0] sum;
    sum = 0;
    for (integer j = 0; j < 10; j++) begin
        sum += popcount6(inp[(j*6)+:6]);
    end
    sum += popcount6({2'b0,inp[63:60]});
    return sum;    
endfunction

// 64 input bit scan
// (also known as leading zero counter or priority encoder)
// return value:
// bitscan64[6:1] is an index to the highest 1-bit in the input
// bitscan64[0]   is 1 if all input bits are zero
function [6:0] bitscan64A;
    input [63:0] m0;         // 64 bits input
    logic [5:0]  r;          // index to highest 1-bit
    logic        iszero;     // indicates that input is zero

    logic [15:0] m1;         // subdivision
    logic [3:0]  m2;         // subdivision
    r = 0;

    // divide into four blocks of 16 bits each
    if (|m0[63:48]) begin
        r[5:4] = 3;          // r[5:4] indicates which 16-bit block contains the highest 1-bit
        m1 = m0[63:48];      // m1 is the 16-bit block that contains the highest 1-bit
    end else if (|m0[47:32]) begin
        r[5:4] = 2;
        m1 = m0[47:32];
    end else if (|m0[31:16]) begin
        r[5:4] = 1;
        m1 = m0[31:16];
    end else begin
        r[5:4] = 0;
        m1 = m0[15:0];
    end
    
    // now subdivide m1 into four blocks of 4 bits each
    if (|m1[15:12]) begin
        r[3:2] = 3;          // r[3:2] indicates which 4-bit block of m1 contains the highest 1-bit
        m2 = m1[15:12];      // m2 is the 4-bit block that contains the highest 1-bit
    end else if (|m1[11:8]) begin
        m2 = m1[11:8];
        r[3:2] = 2;
    end else if (|m1[7:4]) begin
        m2 = m1[7:4];
        r[3:2] = 1;
    end else begin
        m2 = m1[3:0];
        r[3:2] = 0;
    end
    
    // finally, test each of the four bits in m2
    if (m2[3])      r[1:0] = 3; // r[1:0] indicates which of the 4 bit bits in m2 contains the highest 1-bit
    else if (m2[2]) r[1:0] = 2;
    else if (m2[1]) r[1:0] = 1;
    else            r[1:0] = 0;
    
    // test if everything is zero
    iszero = ~|m2;

    // return two values
    return {r, iszero};
endfunction


// 64 input bit scan, alternative implementation
// (this one is slightly slower)
// return value:
// bitscan64[6:1] is an index to the highest 1-bit in the input
// bitscan64[0]   is 1 if all input bits are zero
function [6:0] bitscan64B;
    input [63:0] m0;         // 64 bits input
    logic [5:0]  r;          // index to highest 1-bit
    logic        iszero;     // indicates that input is zero
    logic [3:0]  m1;         // subdivision flags
    logic [3:0]  m2;         // subdivision
    r = 0;

    if (|m0[63:48]) begin
        r[5:4] = 3;
        m1[3] = |m0[63:60];
        m1[2] = |m0[59:56];
        m1[1] = |m0[55:52];
        m1[0] = |m0[51:48];
        
    end else if (|m0[47:32]) begin
        r[5:4] = 2;
        m1[3] = |m0[47:44];
        m1[2] = |m0[43:40];
        m1[1] = |m0[39:36];
        m1[0] = |m0[35:32];

    end else if (|m0[31:16]) begin
        r[5:4] = 1;
        m1[3] = |m0[31:28];
        m1[2] = |m0[27:24];
        m1[1] = |m0[23:20];
        m1[0] = |m0[19:16];
        
    end else begin
        r[5:4] = 0;
        m1[3] = |m0[15:12];
        m1[2] = |m0[11:8];
        m1[1] = |m0[7:4];
        m1[0] = |m0[3:0]; 
    end
    
    if (m1[3]) begin
        r[3:2] = 3;
    end else if (m1[2]) begin
        r[3:2] = 2;
    end else if (m1[1]) begin
        r[3:2] = 1;
    end else begin
        r[3:2] = 0;
    end
    
    // extract the 4-bit block that contains the highest 1-bit
    m2 = m0[{r[5:2],2'b0}+: 4];
    
    if      (m2[3]) r[1:0] = 3;
    else if (m2[2]) r[1:0] = 2;
    else if (m2[1]) r[1:0] = 1;
    else            r[1:0] = 0;
    
    // test if everything is zero
    iszero = ~|m2;

    // return two values
    return {r, iszero};
endfunction


// 64 input bit scan, alternative implementation
// (this one appears to be the fastest)
// return value:
// bitscan64[6:1] is an index to the highest 1-bit in the input
// bitscan64[0]   is 1 if all input bits are zero
function [6:0] bitscan64C;
    input [63:0] m0;         // 64 bits input
    logic [5:0]  r;          // index to highest 1-bit
    logic        iszero;     // indicates that input is zero
    logic [15:0] m1;         // subdivision flags
    logic [3:0]  m2;         // subdivision
    logic [3:0]  m3;         // subdivision
    r = 0;
    
    m1[15] = |m0[63:60];
    m1[14] = |m0[59:56];
    m1[13] = |m0[55:52];
    m1[12] = |m0[51:48];
    m1[11] = |m0[47:44];
    m1[10] = |m0[43:40];
    m1[9]  = |m0[39:36];
    m1[8]  = |m0[35:32];
    m1[7]  = |m0[31:28];
    m1[6]  = |m0[27:24];
    m1[5]  = |m0[23:20];
    m1[4]  = |m0[19:16];
    m1[3]  = |m0[15:12];
    m1[2]  = |m0[11:8];
    m1[1]  = |m0[7:4];
    m1[0]  = |m0[3:0];
    
    m2[3]  = |m1[15:12]; 
    m2[2]  = |m1[11:8]; 
    m2[1]  = |m1[7:4]; 
    m2[1]  = |m1[3:0];

    if (m2[3]) begin
        r[5:4] = 3;
        if      (m1[15]) r[3:2] = 3;
        else if (m1[14]) r[3:2] = 2;
        else if (m1[13]) r[3:2] = 1;
        else             r[3:2] = 0;
        
    end else if (m2[2]) begin
        r[5:4] = 2;
        if      (m1[11]) r[3:2] = 3;
        else if (m1[10]) r[3:2] = 2;
        else if (m1[9])  r[3:2] = 1;
        else             r[3:2] = 0;

    end else if (m2[1]) begin
        r[5:4] = 1;
        if      (m1[7])  r[3:2] = 3;
        else if (m1[6])  r[3:2] = 2;
        else if (m1[5])  r[3:2] = 1;
        else             r[3:2] = 0;
        
    end else begin
        r[5:4] = 0;
        if      (m1[3])  r[3:2] = 3;
        else if (m1[2])  r[3:2] = 2;
        else if (m1[1])  r[3:2] = 1;
        else             r[3:2] = 0;
        
    end
    
    // extract the 4-bit block that contains the highest 1-bit
    m3 = m0[{r[5:2],2'b0}+: 4];
    
    if      (m3[3]) r[1:0] = 3;
    else if (m3[2]) r[1:0] = 2;
    else if (m3[1]) r[1:0] = 1;
    else            r[1:0] = 0;
    
    // test if everything is zero
    iszero = ~|m2;

    // return two values
    return {r, iszero};
endfunction


// This function finds the index to a single bit in a 64-bit input
// where only one bit is set. Used when bitscan relies on the output of roundp2
// Use the formula b = a & ~(a-1) to isolate the lowest set bit before
// calling bitindex. Reverse the order of the bits to find the highest set bit.
// The return value is {r, iszero} where r is the position of the single 1-bit,
// iszero is 1 if all input bits are zero.
// Note that this function does not work if more than one input bit is 1.
function [6:0] bitindex;
    input [63:0] m0;         // 64 bits input
    logic [5:0]  r;          // index to highest 1-bit
    logic        iszero;     // indicates that input is zero
    
    logic [15:0] m2;         // OR combination of groups of four bits
    
    m2[15] = |m0[63:60];
    m2[14] = |m0[59:56];
    m2[13] = |m0[55:52];
    m2[12] = |m0[51:48];
    
    m2[11] = |m0[47:44];
    m2[10] = |m0[43:40];
    m2[9]  = |m0[39:36];
    m2[8]  = |m0[35:32];
    
    m2[7]  = |m0[31:28];
    m2[6]  = |m0[27:24];
    m2[5]  = |m0[23:20];
    m2[4]  = |m0[19:16];
    
    m2[3]  = |m0[15:12];
    m2[2]  = |m0[11:8];
    m2[1]  = |m0[7:4];
    m2[0]  = 0;//|m0[3:0]; // not used
    
    r[5] = m2[8]|m2[9]|m2[10]|m2[11]|m2[12]|m2[13]|m2[14]|m2[15];
    r[4] = m2[4]|m2[5]|m2[6]|m2[7]|m2[12]|m2[13]|m2[14]|m2[15];
    r[3] = m2[2]|m2[3]|m2[6]|m2[7]|m2[10]|m2[11]|m2[14]|m2[15];
    r[2] = m2[1]|m2[3]|m2[5]|m2[7]|m2[9]|m2[11]|m2[13]|m2[15];
    r[1] = m0[2]|m0[3]|m0[6]|m0[7]|m0[10]|m0[11]|m0[14]|m0[15]|
           m0[18]|m0[19]|m0[22]|m0[23]|m0[26]|m0[27]|m0[30]|m0[31]|
           m0[34]|m0[35]|m0[38]|m0[39]|m0[42]|m0[43]|m0[46]|m0[47]|
           m0[50]|m0[51]|m0[54]|m0[55]|m0[58]|m0[59]|m0[62]|m0[63];
    r[0] = m0[1]|m0[3]|m0[5]|m0[7]|m0[9]|m0[11]|m0[13]|m0[15]|
           m0[17]|m0[19]|m0[21]|m0[23]|m0[25]|m0[27]|m0[29]|m0[31]|
           m0[33]|m0[35]|m0[37]|m0[39]|m0[41]|m0[43]|m0[45]|m0[47]|
           m0[49]|m0[51]|m0[53]|m0[55]|m0[57]|m0[59]|m0[61]|m0[63];
    
    iszero = (~|r) && ~(m0[0]);
    
    // return two values
    return {r, iszero};
endfunction


// reverse order of bits
function [7:0] reversebits8;
    input [7:0] in;          // 8 bits input    
    return {in[0],in[1],in[2],in[3],in[4],in[5],in[6],in[7]};
endfunction

// reverse order of bits
function [15:0] reversebits16;
    input [15:0] in;         // 16 bits input    
    return {reversebits8(in[7:0]),reversebits8(in[15:8])};
endfunction

// reverse order of bits
function [31:0] reversebits32;
    input [31:0] in;         // 32 bits input    
    return {reversebits8(in[7:0]),reversebits8(in[15:8]),reversebits8(in[23:16]),reversebits8(in[31:24])};
endfunction

// reverse order of bits
function [63:0] reversebits64;
    input [63:0] in;         // 32 bits input    
    return {reversebits8(in[7:0]),reversebits8(in[15:8]),reversebits8(in[23:16]),reversebits8(in[31:24]),
    reversebits8(in[39:32]),reversebits8(in[47:40]),reversebits8(in[55:48]),reversebits8(in[63:56])};
endfunction

// Truth table lookup with three inputs for truth_tab3 instruction
function  [`RB1:0] truth_table_lookup;
    input [`RB1:0] in1;      // input 1
    input [`RB1:0] in2;      // input 2
    input [`RB1:0] in3;      // input 3
    input [7:0]    ttable;   // 8 bit truth table
    logic [`RB1:0] res;      // result
    for (integer k = 0; k < `RB; k++) begin       // loop through bits
        res[k] = ttable[{in3[k],in2[k],in1[k]}];  // lookup with 3 bits index
    end
    truth_table_lookup = res;// result
endfunction
