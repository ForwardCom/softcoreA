//////////////////////////////////////////////////////////////////////////////////
// Engineer:       Agner Fog
// 
// Create Date:    2020-06-06
// Last modified:  2021-08-07
// Module Name:    defines.vh
// Project Name:   ForwardCom soft core
// Target Devices: Artix 7
// Tool Versions:  Vivado v. 2020.1
// License:        CERN-OHL-W v. 2 or later
// Description:    Various global constants
//////////////////////////////////////////////////////////////////////////////////

// Important: Remember to set the clock frequency to the value in the config_.. file

// Choose configuration:
//`include "config_r32.vh"             // 32 bit registers, 32kB data RAM, 64 kB code RAM, 68 MHz
`include "config_r64.vh"               // 64 bit registers, 32kB data RAM, 64 kB code RAM, 58 MHz


`timescale 1ns / 1ps                   // set time scale for simulation

////////////////////////////////////////////////////////////////////////////////////
//
//          Constants used during building
//
////////////////////////////////////////////////////////////////////////////////////

 
// Fields in the instruction templates
`define IL     31:30                   // instruction length field
`define MODE   29:27                   // mode field
`define ILMODE 31:27                   // combined IL and mode field
`define OP1    26:21                   // op1 field
`define RD     20:16                   // RD: destination operand field
`define M      15                      // M bit extends mode field
`define OT     15:13                   // operand type field, including M bit
`define RS     12:8                    // RS: first source operand field
`define MASK   7:5                     // mask field
`define RT     4:0                     // RT: second source operand field
`define MODE   29:27                   // mode field
`define IM1    7:0                     // immediate field in format B, 8 bits
`define IM1S   7                       // sign bit of IM1
`define IM2E   47:32                   // immediate field 2 in format E, 16 bits
`define IM2ES  47                      // sign bit of IM2E
`define IM3E   53:48                   // immediate field 3 in format E, 6 bits
`define IM3EX  55:48                   // immediate field 3 in format E, extended into OP2
`define IM3EXS 55                      // sign bit of IM3EX
`define OP2    55:54                   // op2 field in format E
`define RU     60:56                   // RU: third source operand field in format E
`define MODE2  63:61                   // mode2 field in format E

// Values for operand type
`define OT_INT8     0                  //  8 bit integer
`define OT_INT16    1                  // 16 bit integer
`define OT_INT32    2                  // 32 bit integer
`define OT_INT64    3                  // 64 bit integer
`define OT_INT128   4                  // 128 bit integer
`define OT_FLOAT32  5                  // single precision float
`define OT_FLOAT64  6                  // double precision float
`define OT_FLOAT128 7                  // quadruple precision float
`define OT_FLOAT16  1                  // half precision float

// Values for instruction category
`define CAT_MULTI  2'b00               // multi-format instruction
`define CAT_SINGLE 2'b01               // single-format instruction
`define CAT_JUMP   2'b10               // control transfer instruction, i.e. jump, call, return

// Values for instruction format
`define FORMAT_A  2'b00                // format A 
`define FORMAT_E  2'b01                // format E
`define FORMAT_B  2'b10                // format B
`define FORMAT_C  2'b11                // format C

// Values for use of registers
`define REG_UNUSED  0                  // register is unused
`define REG_OPERAND 1                  // register is a general purpose register input operand
`define REG_VECTOR  2                  // register is a vector register input operand
`define REG_SYSTEM  3                  // register is a system register
`define REG_POINTER 4                  // register is a memory base pointer (RS only)
`define REG_INDEX   4                  // register is a scaled array index (RT only)
`define REG_LENGTH  5                  // register specifies vector length (RT only)

// Values for scale factor applied to index register
`define SCALE_NONE  0                  // index is not scaled
`define SCALE_OS    1                  // index is scaled by operand size
`define SCALE_MINUS 2                  // index is scaled by -1
`define SCALE_UNDEF 2'bXX              // no index register

// Values for address offset field
`define OFFSET_NONE  0                 // no offset to pointer register
`define OFFSET_1     1                 // 8 bit offset in IM1, scaled by operand size
`define OFFSET_2     2                 // 16 bit offset in IM2, not scaled
`define OFFSET_3     3                 // 24, 32, or 64 bit offset in IM2 or IM4, not scaled

// Values for immediate operand field
`define IMMED_NONE  0                  // no immediate operand
`define IMMED_1     1                  // 8 bit immediate operand in IM1
`define IMMED_2     2                  // 16 bit immediate operand in {IM2,IM1} for format C, or IM2 for format E
`define IMMED_3     3                  // 32 or 64 bit immediate operand

// Values for result type
`define RESULT_REG   0                 // result is a register, general purpose or vector
`define RESULT_SYS   1                 // result is a system register.
`define RESULT_MEM   2                 // result is a memory output
`define RESULT_NONE  3                 // result is nothing or none of the above

// Fallback option
`define FALLBACK_NONE   0              // no fallback
`define FALLBACK_SOURCE 1              // first source register is used for fallback
`define FALLBACK_RU     2              // separate fallback register in RU field
`define FALLBACK_RS     3              // separate fallback register in RS field
`define FALLBACK_RT     4              // separate fallback register in RT field

// Special register numbers in register file
`define NUMCONTR       32              // numeric control register
`define THREADP        33              // thread pointer
`define DATAP          34              // data section pointer

// Instruction OP1 values. These are not necessarily identical to the values in the assembler and emulator
`define II_NOP              0          // nop instruction
`define II_MOVE             2          // move instruction
`define II_STORE            1          // write to memory
`define II_SIGN_EXTEND      4          // sign_extend
`define II_SIGN_EXTEND_ADD  5          // sign_extend_add
`define II_COMPARE          7          // compare
`define II_ADD              8          // add
`define II_SUB              9          // sub
`define II_SUB_REV         10          // sub_rev
`define II_MUL             11          // mul
`define II_MUL_HI          12          // mul_hi
`define II_MUL_HI_U        13          // mul_hi_u
`define II_DIV             14          // div
`define II_DIV_U           15          // div_u
`define II_DIV_REV         16          // div_rev 
`define II_REM             18          // rem
`define II_REM_U           19          // rem_u
`define II_MIN             20          // min
`define II_MIN_U           21          // min_u
`define II_MAX             22          // max
`define II_MAX_U           23          // max_u
`define II_AND             26          // and
`define II_OR              27          // or
`define II_XOR             28          // xor
`define II_MUL_2POW        32          // mul_2pow
`define II_SHIFT_LEFT      32          // shift_left
`define II_ROTATE          33          // rotate
`define II_SHIFT_RIGHT_S   34          // shift_right_s
`define II_SHIFT_RIGHT_U   35          // shift_right_u
`define II_CLEAR_BIT       36          // clear_bit
`define II_SET_BIT         37          // set_bit
`define II_TOGGLE_BIT      38          // toggle_bit
`define II_TEST_BIT        39          // test_bit
`define II_TEST_BITS_AND   40          // test_bits_and
`define II_TEST_BITS_OR    41          // test_bits_or
`define II_ADD_FLOAT16     44          // add float16
`define II_SUB_FLOAT16     45          // sub float16
`define II_MUL_FLOAT16     46          // mul float16
`define II_MUL_ADD_FLOAT16 48          // mul_add float16
`define II_MUL_ADD         49          // mul_add
`define II_MUL_ADD2        50          // mul_add2
`define II_ADD_ADD         51          // add_add
`define II_SELECT_BITS     52          // select_bits
`define II_FUNNEL_SHIFT    53          // funnel_shift

`define II_STOREI           8          // write immediate to memory, format 2.5
`define II_FENCE           16          // fence instruction, format 2.5
`define II_CMPSWAP         18          // compare_swap instruction format, 2.5 
`define II_XTR_STORE       32          // extract_store instruction
`define II_CLEAR           58          // clear instruction
`define II_WR_SPEC         33          // write_spec instruction
`define II_WR_CAPA         35          // write_capabilities instruction
`define II_ONE_OP           4          // multiformat instructions with one input have op1 <= II_ONE_OP 
`define II_VECTORS_USED    59          // vectors_used instruction
`define II_UNCOND_JUMP     15          // unconditional jump or call <= this value
`define II_INDIRECT_JUMP   58          // indirect jump instructions in format 1.6B or 2.5.0
`define II_JUMP_RELATIVE   60          // multiway jump instructions in format 1.6A
`define II_RETURN          62          // return instruction
`define II_25_VECT         32          // first vector instruction in format 2.5A
`define II_31_VECT         32          // first vector instruction in format 3.1A

`define II_3OP_FIRST       48          // first multiformat instruction with three input operands 
`define II_3OP_LAST        55          // last multiformat instruction with three input operands
`define II_COMPARE_FIRST   26          // first conditional jump instruction with no result register   
`define II_COMPARE_LAST    47          // last conditional jump instruction with no result register   

// Instructions with IM3 used for option bits in format E. Used in addressgenerator.sv
// II_COMPARE, II_SIGN_EXTEND_ADD, II_TEST_BIT, II_TEST_BITS_AND, II_TEST_BITS_OR,
// II_DIV, II_DIV_REV, `II_DIV_U
// II_MUL_ADD_FLOAT16, II_MUL_ADD, II_MUL_ADD2, II_ADD_ADD, 

// Instructions with first and last operands swapped
// II_SUB_REV, II_DIV_REV, II_MUL_ADD2 


// Instructions with half precision operands
`define II_ADD_H14         40          // half precision add format 1.4
`define II_MUL_H14         41          // half precision mul format 1.4

// Other single format instructions
// Format 1.1C
`define II_MOVEU11          3          // move 16 bits zero extended format 1.1C
`define II_SHIFT_MOVE_11    4          // shift left by IM1, move
`define II_MOVE11_LAST      5          // last instruction with 1 operand in format 1.1C
`define II_ADD11            6          // add 16 bits sign extended
`define II_MUL11            8          // multiply 16 bits sign extended
`define II_SHIFT_ADD_11    10          // shift left by IM1, add
`define II_SHIFT_AND_11    12          // shift left by IM1, and
`define II_SHIFT_OR_11     14          // shift left by IM1, or
`define II_SHIFT_XOR_11    16          // shift left by IM1, xor
`define II_ADDSHIFT16_11   18          // shift left by 16, add

// Format 1.2B
`define II_GETLEN_12        0          // getlen instruction format 1.2
`define II_GETNUM_12        1          // getnum instruction format 1.2

// Format 1.8B
`define II_SHIFT_ABS18      0          // abs
`define II_BITSCAN_18       2          // bitscan
`define II_ROUNDP2_18       3          // roundp2
`define II_POPCOUNT_18      4          // popcount
`define II_READ_SPEC18     32          // read_spec 
`define II_WRITE_SPEC18    33          // read_spec
`define II_READ_CAP18      34          // read_capabilities
`define II_WRITE_CAP18     35          // write_capabilities
`define II_READ_PERF18     36          // read_perf. must be even
`define II_READ_PERFS18    37          // read_perfs = II_READ_PERF18 + 1
`define II_READ_SYS18      38          // read_sys
`define II_WRITE_SYS18     39          // write_sys
`define II_INPUT_18        62          // input instruction format 1.2 and 1.8
`define II_OUTPUT_18       63          // output instruction format 1.2 and 1.8

// Format 2.x
`define II_MOVE_BITS        0          // move bits instruction op1, single format 2.X.7-0.1
`define II2_MOVE_BITS       1          // move bits instruction op2, single format 2.X.7-0.1
`define II_MASK_LENGTH      1          // mask length instruction op1, single format 2.2.7-1.1
`define II2_MASK_LENGTH     1          // mask length instruction op2, single format 2.2.7-1.1
`define II_TRUTH_TAB3       8          // truth_tab3 instruction op1, single format 2.0.6 or 2.2.6 - 8.1
`define II2_TRUTH_TAB3      1          // truth_tab3 op2

// Format 2.6A
`define II_LOAD_HI_26       0          // load_hi instruction format 2.6

// Format 2.9A
`define II_MOVE_HI_29       0          // move high 32 bit instruction format 2.9
`define II_INSERT_HI_29     1          // insert_hi
`define II_ADDU_29          2          // add 
`define II_SUBU_29          3          // sub 
`define II_ADD_HI_29        4          // add 
`define II_AND_HI_29        5          // and high 
`define II_OR_HI_29         6          // or high 
`define II_XOR_HI_29        7          // xor high
`define II_ADDRESS_29      32          // address

// jump instructions
`define IJ_SUB_JZ               0      // subtract, jump if zero
`define IJ_SUB_JNEG             2      // subtract, jump if negative
`define IJ_SUB_JPOS             4      // subtract, jump if positive
`define IJ_SUB_JOVFLW           6      // subtract, jump if overflow
`define IJ_SUB_JBORROW          8      // subtract, jump if borrow
`define IJ_AND_JZ              10      // and, jump if zero
`define IJ_OR_JZ               12      // or,  jump if zero
`define IJ_XOR_JZ              14      // xor, jump if zero
`define IJ_ADD_JZ              16      // add, jump if zero
`define IJ_ADD_JNEG            18      // add, jump if negative
`define IJ_ADD_JPOS            20      // add, jump if positive
`define IJ_ADD_JOVFLW          22      // add, jump if overflow
`define IJ_ADD_JCARRY          24      // add, jump if carry
`define IJ_TEST_BIT_JTRUE      26      // test single bit, jump if 1
`define IJ_TEST_BITS_AND       28      // test bits, jump if all 1
`define IJ_TEST_BITS_OR        30      // test bits, jump if all 1
`define IJ_COMPARE_JEQ         32      // compare, jump if equal
`define IJ_COMPARE_JSB         34      // compare, jump if signed below
`define IJ_COMPARE_JSA         36      // compare, jump if signed above
`define IJ_COMPARE_JUB         38      // compare, jump if unsigned below
`define IJ_COMPARE_JUA         40      // compare, jump if unsigned above
`define IJ_INC_COMP_JBELOW     48      // increment. jump if below n
`define IJ_INC_COMP_JABOVE     50      // increment. jump if above n
`define IJ_SUB_MAXLEN_JPOS     52      // subtract max vector length, jump while positive
`define IJ_LAST_CONDITIONAL    55      // last two-way conditional jump
`define IJ_JUMP_INDIRECT_REG   58      // indirect jump to register, format 1.7
`define IJ_JUMP_INDIRECT_MEM   58      // indirect jump to memory address, format 1.6 and 2.5.0
`define IJ_JUMP_DIRECT         58      // direct unconditional jump, format 2.5.4 and 3.1.1
`define IJ_JUMP_RELATIVE       60      // jump with relative pointers in memory, format 1.6 and 2.5.0
`define IJ_RETURN              62      // return, format 1.6
`define IJ_SYSRETURN           62      // system return, format 1.7
`define IJ_SYSCALL             63      // system call
`define IJ_TRAP                63      // trap (software interrupt, debug breakpoint), format 1.7
`define IJ_CONDITIONAL_TRAP    63      // conditional trap. Format 2.5.3. Not supported. 

// Instruction ID's opx in execution unit for single-format instructions
// These values are arbitrary and may be changed. Must be bigger than 63
`define IX_UNDEF              127      // unknown instruction
`define IX_ABS                 64      // abs format 1.8
`define IX_BIT_SCAN            66      // bitscan format 1.8
`define IX_ROUNDP2             67      // roundp2 format 1.8
`define IX_POPCOUNT            68      // popcount format 1.8
`define IX_READ_SPEC           69      // bitscan format 1.8
`define IX_WRITE_SPEC          70      // write_spec format 1.8
`define IX_READ_CAPABILITIES   71      // read_capab format 1.8
`define IX_WRITE_CAPABILITIES  72      // write_capab format 1.8
`define IX_READ_PERF           74      // read_perf format 1.8
`define IX_READ_PERFS          75      // read_perfs format 1.8
`define IX_READ_SYS            76      // read_sys format 1.8
`define IX_WRITE_SYS           77      // write_sys format 1.8
`define IX_INPUT               78      // input format 1.8
`define IX_OUTPUT              79      // output format 1.8
`define IX_MOVE_BITS1          80      // move bits instruction, shifting left
`define IX_MOVE_BITS2          81      // move bits instruction, shifting right
`define IX_SHIFT32             82      // move format 2.9: shift left 32 bits 
`define IX_INSERT_HI           83      // insert_high format 2.9. replace high 32 bits 
`define IX_ADDRESS             84      // address instruction format 2.9. (replaced by move)
`define IX_TRUTH_TAB3          85      // truth_tab3 instruction
`define IX_UNCOND_JUMP         90      // unconditional direct self-relative jump
`define IX_INDIRECT_JUMP       91      // indirect jump to register or memory
`define IX_RELATIVE_JUMP       92      // indirect jump with table of relative addresses

 