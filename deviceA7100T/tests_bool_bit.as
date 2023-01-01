/**************************  tests_bool_bit.as  *******************************
* Author:        Agner Fog
* date created:  2021-06-27
* last modified: 2021-07-20
* Version:       1.11
* Project:       ForwardCom Test suite, assembly code
* Description:   Test boolean and bit manipulation instructions with general 
*                purpose registers
*
* This test program will test boolean and bit manipulation instructions and 
* output a list of which instructions are working for int8, int16, int32, 
* and int64 operands.
*
* Copyright 2021 GNU General Public License v. 3 http://www.gnu.org/licenses
******************************************************************************/

// Library functions in libc_light.li
extern _puts:     function reguse=3,0            // write string + linefeed to stdout
extern _printf:   function reguse=0xF,0          // write formatted string to stdout

const section read ip                            // read-only data section
// Text strings:

text1: int8 "\nForwardCom test suite\nTest general purpose register bit manipulation instructions"  // intro text,
       int8 "\nPress Run to continue"
       int8 "\n                      int8   int16  int32  int64", 0                                 // and heading
newline: int8 "\n", 0                                                                               // newline
press_run: int8 "\nPress Run to continue", 0

format1: int8 "\n%-22s%3c%7c%7c%7c", 0           // format string for printing results

// text strings for each instruction:
text_and: int8 "and", 0
text_or:  int8 "or", 0
text_xor: int8 "xor", 0

text_shift_left: int8 "shift left", 0
text_shift_right_signed: int8 "shift right signed", 0
text_shift_right_unsigned: int8 "shift right unsigned", 0
text_funnel_shift: int8 "funnel shift", 0
text_rotate: int8 "rotate", 0

text_clear_bit: int8 "clear_bit", 0
text_set_bit: int8 "set_bit", 0
text_toggle_bit: int8 "toggle_bit", 0

text_test_bit: int8 "test_bit", 0
text_test_bits_and: int8 "test_bits_and", 0
text_test_bits_or: int8 "test_bits_or", 0
text_compare: int8 "compare", 0

text_bitscan: int8 "bitscan", 0
text_roundp2: int8 "roundp2", 0
text_popcount: int8 "popcount", 0
text_truthtab3: int8 "truth_tab3", 0

text_move_high: int8 "move high", 0
text_insert_high: int8 "insert high", 0
text_move_bits: int8 "move_bits", 0

const end


code section execute                             // code section

__entry_point function public
_main function public

/* register use:
r0:  bits indicating success for int8, int16, int32, int64
r1:  operand
r2:  operand
r3:  result
r4:  scratch
r6:  int64 supported
*/

// print intro text and heading
int64  r0 = address [text1]                      // calculate address of string
call   _puts                                     // call puts. parameter is in r0

breakpoint                                       // debug breakpoint

int    r1 = 1
int    capab2 = write_capabilities(r1, 0)        // disable error trap for unknown instructions

// arbitrary test data
% A = 0x12345555
% B = 0x5678CEFC
% C = 0xABCDF0F0


// Test and

int32  r1 = A
int32  r2 = B

int8   r3 = r1 & r2                              // int8 and
int32  r0 = r3 == (A & B & 0xFF)                 // check result, set bit 0 if success

int16  r3 = r1 & r2                              // int16 and
int32  r4 = r3 == (A & B & 0xFFFF)               // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = r1 & r2                              // int32 and
int32  r4 = r3 == (A & B)                         // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r1 |= 0x12345
int64  r2 |= C

int64  r3 = r1 & r2                              // 64 bit and
int32  r4 = r3 == (0x12345 & C)                  // check lower half of result
uint64 r3 >>= 32                                 // shift down upper half
int64  r6 = r3 == (A & B) && r4                  // check upper half of result
int32  r0 |= 8, mask = r6                        // set bit 2 if success

int64  r1 = address [text_and]
call   print_result


// Test or

int32  r1 = A
int32  r2 = B

int8   r3 = r1 | r2                              // int8 or
int32  r0 = r3 == ((A | B) & 0xFF)               // check result, set bit 0 if success

int16  r3 = r1 | r2                              // int16 or
int32  r4 = r3 == ((A | B) & 0xFFFF)             // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = r1 | r2                              // int32 or
int32  r4 = r3 == (A | B)                        // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r1 |= 0x12345
int64  r2 |= C

int64  r3 = r1 | r2                              // 64 bit or
int32  r4 = r3 == (0x12345 | C)                  // check lower half of result
uint64 r3 >>= 32                                 // shift down upper half
int64  r6 = r3 == (A | B) && r4                  // check upper half of result
int32  r0 |= 8, mask = r6                        // set bit 2 if success

int64  r1 = address [text_or]
call   print_result


// Test xor

int32  r1 = A
int32  r2 = B

int8   r3 = r1 ^ r2                              // int8 xor
int32  r0 = r3 == ((A ^ B) & 0xFF)               // check result, set bit 0 if success

int16  r3 = r1 ^ r2                              // int16 xor
int32  r4 = r3 == ((A ^ B) & 0xFFFF)             // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = r1 ^ r2                              // int32 xor
int32  r4 = r3 == (A ^ B)                        // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r1 |= 0x12345
int64  r2 |= C

int64  r3 = r1 ^ r2                              // 64 bit xor
int32  r4 = r3 == (0x12345 ^ C)                  // check lower half of result
uint64 r3 >>= 32                                 // shift down upper half
int64  r6 = r3 == (A ^ B) && r4                  // check upper half of result
int32  r0 |= 8, mask = r6                        // set bit 2 if success

int64  r1 = address [text_xor]
call   print_result


// Test shift left

int32  r1 = A

int8   r3 = r1 << 3                              // int8 shift
int32  r0 = r3 == (A << 3 & 0xFF)                // check result, set bit 0 if success
int8   r3 = r1 << 0                              // int8 shift
int    r0 = r3 == (A & 0xFF) && r0

int16  r3 = r1 << 12                             // int16 shift
int32  r4 = r3 == (A << 12 & 0xFFFF)             // check result, set bit 0 if success
int16  r3 = r1 << -1                             // int16 shift overflow
int    r4 = (r3 == 0) && r4
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int    r2 = 18
int32  r3 = r1 << r2                             // int32 shift
int32  r4 = r3 == (A << 18 & 0xFFFFFFFF)         // check result, set bit 0 if success
int32  r3 = r1 << 1                              // int32 shift
int32  r4 = (r3 == (A << 1 & 0xFFFFFFFF)) && r4
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r3 = r1 << 36                             // int64 shift
int64  r4 = A << 36
int64  r4 = r3 == r4
uint64 r3 >>= 36
int32  r4 = r3 == (A & 0x0FFFFFFF) && r4
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_shift_left]
call   print_result


// Test shift right signed

shiftrightsigned:
int32  r1 = A

%A1 = 0xA3
int8   r3 = r1 >> 3                              // int8 shift
int32  r0 = r3 == (A & 0xFF) >> 3                // check result, set bit 0 if success
int8   r3 = r1 >> 0                              // int8 shift
int    r0 = r3 == (A & 0xFF) && r0
int    r2 = A1                                   // negative number
int8   r3 = r2 >> 3                              // int8 shift
int32  r0 = r3 == (A1 >> 3 | 0xE0) && r0         // check result, set bit 0 if success

%A2 = 0xBC62
int16  r3 = r1 >> 9                              // int16 shift
int32  r4 = r3 == (A & 0xFFFF) >> 9              // check result, set bit 0 if success
int16  r3 = r1 >> 70                             // int16 shift overflow
int    r4 = (r3 == 0) && r4
int    r2 = A2
int16  r3 = r2 >> 3
int32  r4 = r3 == (A2 >> 3 | 0xE000) && r4       // check result, set bit 0 if success
int32  r0 |= 2, mask = r4                        // set bit 1 if success

%A3 = 0x81ABCD25
int32  r1 = A3
int    r2 = 18
int32  r3 = r1 >> r2                             // int32 shift
uint32 r4 = r3 == (A3 >> 18 & 0xFFFFFFFF | 0xFFFFC000)   // check result, set bit 0 if success
int32  r3 = r1 >> 33                             // overflow of signed shift
int32  r4 = (r3 == -1) && r4
int32  r0 |= 4, mask = r4                        // set bit 2 if success

%A4 = 0x81ABCD2512345678
int64  r1 = A4
int64  r3 = r1 >> 35                             // int64 shift
int64  r4 = A4 >> 35
int64  r4 = r3 == r4
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_shift_right_signed]
call   print_result


// Test shift right unsigned

int32  r1 = A

%A1 = 0xA3
uint8  r3 = r1 >> 3                              // int8 shift
int32  r0 = r3 == (A & 0xFF) >> 3                // check result, set bit 0 if success
uint8  r3 = r1 >> 0                              // int8 shift
int    r0 = r3 == (A & 0xFF) && r0
int    r2 = A1                                   // negative number
uint8  r3 = r2 >> 3                              // int8 shift
int32  r0 = r3 == A1 >> 3 && r0                  // check result, set bit 0 if success

%A2 = 0xBC62
uint16 r3 = r1 >> 9                              // int16 shift
int32  r4 = r3 == (A & 0xFFFF) >> 9              // check result, set bit 0 if success
uint16 r3 = r1 >> 70                             // int16 shift overflow
int    r4 = (r3 == 0) && r4
int    r2 = A2
uint16 r3 = r2 >> 3
int32  r4 = r3 == A2 >> 3 && r4                  // check result, set bit 0 if success
int32  r0 |= 2, mask = r4                        // set bit 1 if success

%A3 = 0x81ABCD25
int32  r1 = A3
int    r2 = 18
uint32 r3 = r1 >> r2                             // int32 shift
uint32 r4 = r3 == (A3 >> 18 & 0xFFFFFFFF)        // check result, set bit 0 if success
uint32 r3 = r1 >> 33                             // overflow of unsigned shift
int32  r4 = (r3 == 0) && r4
int32  r0 |= 4, mask = r4                        // set bit 2 if success

%A4 = 0x81ABCD2512345678
int64  r1 = A4
uint64 r3 = r1 >> 35                             // int64 shift
int64  r4 = A4 >>> 35
int64  r4 = r3 == r4
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_shift_right_unsigned]
call   print_result


// Test funnel shift
int    r1 = A
int    r2 = B

int8   r3 = funnel_shift(r1, r2, 5)              // int8 shift
int    r0 = r3 == ((A & 0xFF) >> 5 | (B << 3 & 0xFF)) // check result, set bit 0 if success
int8   r3 = funnel_shift(r1, r2, 0)              // int8 shift
int    r0 = r3 == (A & 0xFF) && r0
int8   r3 = funnel_shift(r1, r2, 8)              // int8 shift
int    r0 = r3 == 0 && r0

int16  r3 = funnel_shift(r1, r2, 10)             // int16 shift
int    r4 = r3 == ((A & 0xFFFF) >> 10 | (B << 6 & 0xFFFF)) // check result, set bit 0 if success
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = funnel_shift(r1, r2, 21)             // int32 shift
int64  r4 = r3 == ((A & 0xFFFFFFFF) >> 21 | (B << 11 & 0xFFFFFFFF)) // check result, set bit 0 if success
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r3 = funnel_shift(r1, r2, 50)             // int64 shift
int64  r4 = r3 == (A >> 50 | B << 14)            // check result, set bit 0 if success
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_funnel_shift]
call   print_result


// Test rotate
int    r1 = B
int8   r3 = rotate(r1, 2)                        // int8 rotate
int    r0 = r3 == ((B << 2 & 0xFF) | (B & 0xFF) >> 6)
int8   r3 = rotate(r1, 0)                        // int8 rotate
int    r0 = r3 == (B & 0xFF) && r0
int    r2 = 0x1234
int8   r3 = rotate(r1, r2)                       // int8 rotate
int    r0 = r3 == ((B << 4 & 0xFF) | (B & 0xFF) >> 4) && r0

int16  r3 = rotate(r1, 0xabcd)                   // int16 rotate
int    r4 = r3 == ((B << 13 & 0xFFFF) | (B & 0xFFFF) >> 3)
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = rotate(r1, -21)                      // int32 rotate
int64  r4 = r3 == ((B << 11 & 0xFFFFFFFF) | (B & 0xFFFFFFFF) >> 21)
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r3 = rotate(r1, 34)                       // int64 rotate
int64  r4 = r3 == ((B << 34) | (B >> 30))
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_rotate]
call   print_result


// Test clear bit
int64  r1 = -1
int8   r3 = clear_bit(r1, 2)                     // int8 clear_bit
int    r0 = r3 == 0xFB

int16  r3 = clear_bit(r1, 8)                     // int16 clear_bit
int    r4 = r3 == 0xFEFF
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = r1 & ~ (1 << 30)     
int32  r3 = clear_bit(r3, 31)                    // int32 clear_bit
int32  r4 = r3 == 0x3FFFFFFF
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r3 = clear_bit(r1, 41)                    // int64 clear_bit
int64  r3 = clear_bit(r3, 41)                    // int64 clear_bit
uint64 r3 >>= 32
int32  r4 = r3 == 0xFFFFFDFF
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_clear_bit]
call   print_result


// Test set bit
int64  r1 = 0
int8   r3 = set_bit(r1, 2)                     // int8 set_bit
int    r0 = r3 == 4

int16  r3 = set_bit(r1, 8)                     // int16 set_bit
int    r4 = r3 == 0x100
int32  r0 |= 2, mask = r4                      // set bit 1 if success

int32  r3 = set_bit(r1, 31)                    // int32 set_bit
int32  r3 = set_bit(r3, 31)                    // int32 set_bit
int32  r4 = r3 == 0x80000000
int32  r0 |= 4, mask = r4                      // set bit 2 if success

int64  r3 = set_bit(r1, 41)                    // int64 set_bit
uint64 r3 >>= 32
int32  r4 = r3 == 0x200
int32  r0 |= 8, mask = r4                      // set bit 3 if success

int64  r1 = address [text_set_bit]
call   print_result


// Test toggle bit
int64  r1 = 0
int8   r3 = toggle_bit(r1, 2)                  // int8 toggle_bit
int    r0 = r3 == 4

int16  r3 = toggle_bit(r1, 8)                  // int16 toggle_bit
int    r4 = r3 == 0x100
int32  r0 |= 2, mask = r4                      // set bit 1 if success

int32  r3 = toggle_bit(r1, 31)                 // int32 toggle_bit
int32  r3 = toggle_bit(r3, 31)                 // int32 toggle_bit
int32  r4 = r3 == 0
int32  r0 |= 4, mask = r4                      // set bit 2 if success

int64  r3 = toggle_bit(r1, 41)                 // int64 toggle_bit
uint64 r3 >>= 32
int32  r4 = r3 == 0x200
int32  r0 |= 8, mask = r4                      // set bit 3 if success

int64  r1 = address [text_toggle_bit]
call   print_result


int64  r0 = address [press_run]                  // press run to continue
call   _printf                                   // print string

breakpoint


// Test test_bit
Test_test_bit:
int32  r1 = 0x12345678
int8   r3 = test_bit(r1, 4)                      // int8 test_bit
int    r0 = r3 == 1
int8   r2 = test_bit(r1, 2)
int    r0 = r2 == 0 && r0

int16  r3 = test_bit(r1, 9)                      // int16 test_bit
int    r4 = r3 == 1
int16  r3 = test_bit(r1, 9), fallback = r2, options = 1
int    r4 = r3 == 0 && r4
int16  r3 = test_bit(r1, 9), fallback = r2, options = 9
int    r4 = r3 == 1 && r4
int    r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = test_bit(r1, 17)                     // int32 test_bit
int    r4 = r3 == 0
int32  r2 = 0xF0
int32  r3 = test_bit(r1, 18), mask = r2, options = 0x20
int    r4 = r3 == r2 && r4
int    r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r3 = test_bit(r1, 38)                     // int64 test_bit
int    r4 = r3 == 1
int32  r2 = 0x71
int32  r3 = test_bit(r1, 75), mask = r2, fallback = r2, options = 0x20
int    r4 = r3 == 0x70 && r4
int32  r3 = test_bit(r1, 75), mask = r2, fallback = r2, options = 0x24
int    r4 = r3 == 0x71 && r4
int    r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_test_bit]
call   print_result


// Test test_bits_and
Test_test_bits_and:
int32  r1 = 0x12345678
int8   r3 = test_bits_and(r1, 0x58)              // int8 test_bits_and
int    r0 = r3 == 1

int16  r2 = test_bits_and(r1, 0x688)             // int16 test_bits_and
int    r4 = r2 == 0
int16  r3 = test_bits_and(r1, 0x688), fallback = r4, options = 2
int    r4 = r3 == 1 && r4
int16  r3 = test_bits_and(r1, 0x688), fallback = r4, options = 7
int    r4 = r3 == 0 && r4
int    r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = test_bits_and(r1, 0x12340678)        // int32 test_bits_and
int    r4 = r3 == 1
int32  r3 = test_bits_and(r1, 0x12346678)
int    r4 = r3 == 0 && r4
int    r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r3 = test_bits_and(r1, 0x67 << 36)        // int64 test_bits_and
int    r4 = r3 == 1
int64  r3 = test_bits_and(r1, 0x6F << 36)
int    r4 = r3 == 0 && r4
int    r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_test_bits_and]
call   print_result


// Test test_bits_or
Test_test_bits_or:
int32  r1 = 0x12345678
int8   r3 = test_bits_or(r1, 0xF0)               // int8 test_bits_or
int    r0 = r3 == 1

int16  r2 = test_bits_or(r1, 0x982)              // int16 test_bits_or
int    r4 = r2 == 0

int16  r3 = test_bits_or(r1, 0x982), fallback = r4, options = 3
int    r4 = r3 == 1 && r4
int16  r3 = test_bits_or(r1, 0x688), fallback = r4, options = 3
int    r4 = r3 == 0 && r4
int    r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = test_bits_or(r1, 0x10000000)         // int32 test_bits_or
int    r4 = r3 == 1
int32  r3 = test_bits_or(r1, 0)
int    r4 = r3 == 0 && r4
int    r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r3 = test_bits_or(r1, 0xF << 36)          // int64 test_bits_or
int    r4 = r3 == 1
int    r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_test_bits_or]
call   print_result


// test compare with mask and fallback
test_compare:
int32  r1 = 5
int32  r2 = 0x56
int8   r3 = compare(r1, r2), options=0, mask = r1// int8 compare
int    r0 = r3 == 4

int16  r3 = compare(r1, r2), options=2, mask = r1, fallback = r1 // int16 compare
int    r4 = r3 == r1
int16  r3 = compare(r1, r2), options=0x12, mask = r2, fallback = r1
int    r4 = r3 == r2 && r4
int16  r3 = compare(r1, r2), options=0x20, mask = r1, fallback = r1
int    r4 = r3 == r1 && r4
int    r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = compare(r1, r2), options=0x31, fallback = r1 // int32 compare
int    r4 = r3 == 0
int    r0 |= 4, mask = r4                        // set bit 2 if success

int64  r3 = compare(r1, r2), options=0x21, fallback = r1 // int64 compare
int    r4 = r3 == 1
int64  r2 = r1 | 1 << 60
int64  r3 = r1 == r2
int    r4 = r3 == 0 && r4
int    r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_compare]
call   print_result


// test bitscan
int    r1 = 0x23412345
int8   r3 = bitscan(r1, 0)                       // int8 bitscan
int    r0 = r3 == 0
int8   r3 = bitscan(r1, 1)
int    r0 = r3 == 6 && r0

int    r2 = 0
int16  r3 = bitscan(r1, 1)                       // int16 bitscan
int    r4 = r3 == 13
int16  r3 = bitscan(r2, 1)                       // zero input
int    r4 = r3 == 0 && r4
int16  r3 = bitscan(r2, 0x11)
int    r4 = r3 == 0xFFFF && r4
int    r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = bitscan(r1, 1)                       // int32 bitscan
int    r4 = r3 == 29
int    r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 10
int64  r3 = bitscan(r1, 1)                       // int64 bitscan
int    r4 = r3 == 29 + 10
int64  r3 = bitscan(r2, 0x10)                    // zero input
int64  r4 = r3 == -1 && r4
int    r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_bitscan]
call   print_result


// test roundp2
int    r1 = 0x23412345
int8   r3 = roundp2(r1, 0)                       // int8 roundp2
int    r0 = r3 == 0x40
int8   r3 = roundp2(r1, 1)
int    r0 = r3 == 0x80

int16  r3 = roundp2(r1, 0)                       // int16 roundp2
int    r4 = r3 == 0x2000
int    r2 = 0
int16  r3 = roundp2(r2, 0)                       // zero input
int    r4 = r3 == 0 && r4
int16  r3 = roundp2(r2, 0x10)                    // zero input
int    r4 = r3 == 0xFFFF && r4
int    r2 = 0x8001
int16  r3 = roundp2(r2, 0)
int    r4 = r3 == 0x8000 && r4
int16  r3 = roundp2(r2, 1)                       // overflow
int    r4 = r3 == 0 && r4
int16  r3 = roundp2(r2, 0x21)
int    r4 = r3 == 0xFFFF && r4
int    r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = roundp2(r1, 0)                       // int32 roundp2
int32  r4 = r3 == 0x20000000
int32  r3 = roundp2(r1, 1)
int32  r4 = r3 == 0x40000000 && r4
int    r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 |= 1 << 40
int64  r3 = roundp2(r1, 0)                       // int64 roundp2
int64  r4 = r3 == 1 << 40
int64  r3 = roundp2(r1, 1)
int64  r4 = r3 == 1 << 41
int    r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_roundp2]
call   print_result


// Test popcount
int    r1 = 0x23412345
int8   r3 = popcount(r1)                         // int8 popcount
int    r0 = r3 == 3

int16  r3 = popcount(r1)                         // int16 popcount
int    r4 = r3 == 6
int    r0 |= 2, mask = r4                        // set bit 1 if success

int64  r1 |= 1 << 40
int32  r3 = popcount(r1)                         // int32 popcount
int    r4 = r3 == 11
int    r0 |= 4, mask = r4                        // set bit 2 if success

int64  r3 = popcount(r1)                         // int64 popcount
int    r4 = r3 == 12
int    r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_popcount]
call   print_result


// Test truth_tab3
int32  r1 = 0xAAAAAAAA
int32  r2 = 0xCCCCCCCC
int32  r3 = 0xF0F0F0F0
int8   r4 = truth_tab3(r1, r2, r3, 0xF2)         // A & ~ B | C
int    r0 = r4 == 0xF2

int16  r4 = truth_tab3(r1, r2, r3, 0xD8)         // A ? B : C
int    r5 = r4 == 0xD8D8
int    r6 = 0x12345
int16  r4 = truth_tab3(r1, r2, r3, 0xD8), options = 1, mask = r6
int    r5 = r4 == 0 && r5
int16  r4 = truth_tab3(r1, r2, r3, 0xD8), options = 2, mask = r6
int    r5 = r4 == 0x2344 && r5
int    r0 |= 2, mask = r5                        // set bit 1 if success

int32  r4 = truth_tab3(r1, r2, r3, 0x72)         // A ? ~B : C
int32  r5 = r4 == 0x72727272
int    r0 |= 4, mask = r5                        // set bit 2 if success

int64  r3 |= 1 << 63
int64  r4 = truth_tab3(r1, r2, r3, 0xFE)         // A | B | C
int64  r5 = r4 == 0x80000000FEFEFEFE
int64  r5 = test_bit(r4, 63), options = 1, fallback = r5
int    r0 |= 8, mask = r5                        // set bit 3 if success


int64  r1 = address [text_truthtab3]
call   print_result


// Test move_bits
int32  r1 = 0
int32  r2 = 0x12345678
int8   r3 = move_bits(r1, r2, 2, 4, 3)           // int8 move_bits
int    r0 = r3 == 0x60

int16  r3 = move_bits(r1, r2, 8, 0, 6)           // int16 move_bits
int    r4 = r3 == 0x16
int    r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = move_bits(r1, r2, 0, 20, 12)         // int32 move_bits
int32  r3 = move_bits(r3, r2, 16, 0, 8)
int    r4 = r3 == 0x67800034
int    r0 |= 4, mask = r4                        // set bit 1 if success

int64  r3 = move_bits(r1, r2, 20, 48, 8)         // int64 move_bits
int64  r4 = r3 == 0x23000000000000
int64  r3 = move_bits(r1, r3, 48, 0, 8)
int64  r4 = r3 == 0x23 && r4
int    r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [text_move_bits]
call   print_result


// Test move high
int64  r1 = 0xabcd1234 << 32
int32  r4 = r1 == 0
uint64 r1 >>= 32
int32  r4 = r1 == 0xabcd1234 && r0
int    r0 = 0x70
int    r0 |= 8, mask = r4
int64  r1 = address [text_move_high]
call   print_result


// Test insert high
int64  r1 = 0x12345678
int64  r1 = insert_hi(r1, 0xabcdef98)
int64  r4 = r1 == 0xabcdef9812345678
int64  r1 >>= 32
int32  r4 = (r1 == 0xabcdef98) && r4
int    r0 = 0x70
int    r0 |= 8, mask = r4
int64  r1 = address [text_insert_high]
call   print_result


int64 r0 = address [newline]
call _puts

breakpoint

int r0 = 0                                       // program return value
return                                           // return from main

_main end


print_result function
// Print the result of a single test. Parameters:
// r0:  4 bits indicating success for for int8, int16, int32, int64. 4 additional bits for printing space (instruction not supported)
// r1:  pointer to text string 

// set up parameter list for printf
int64 sp -= 5*8              // allocate space on stack
int64 [sp] = r1              // text
int r4 = 'N'
int r2 = r0 ? 'Y' : r4       // Y or N
int r5 = test_bit(r0, 4)
int r2 = r5 ? ' ' : r2       // Y/N or space
int64 [sp+0x08] = r2         // result for int8
int r0 >>= 1
int r2 = r0 ? 'Y' : r4       // Y or N
int r5 = test_bit(r0, 4)
int r2 = r5 ? ' ' : r2       // Y/N or space
int64 [sp+0x10] = r2         // result for int16
int r0 >>= 1
int r2 = r0 ? 'Y' : r4       // Y or N
int r5 = test_bit(r0, 4)
int r2 = r5 ? ' ' : r2       // Y/N or space
int64 [sp+0x18] = r2         // result for int32
int r0 >>= 1
int r2 = r0 ? 'Y' : r4       // Y or N
int r5 = test_bit(r0, 4)
int r2 = r5 ? ' ' : r2       // Y/N or space
int64 [sp+0x20] = r2         // result for int64

int64 r0 = address [format1]
int64 r1 = sp
call _printf
int64 sp += 5*8              // release parameter list
return

print_result end


code end