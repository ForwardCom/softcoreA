/**************************  tests_arithmetics.as  ****************************
* Author:        Agner Fog
* date created:  2021-06-06
* last modified: 2022-12-12
* Version:       1.12
* Project:       ForwardCom Test suite, assembly code
* Description:   Test arithmetic instructions with general purpose registers
*
* This test program will test arithmetic instructions and output a list of
* which instructions are working for int8, int16, int32, and int64 operands.
*
* Copyright 2022 GNU General Public License v.3 http://www.gnu.org/licenses
******************************************************************************/

// Library functions in libc_light.li
extern _puts:     function reguse=3,0            // write string + linefeed to stdout
extern _printf:   function reguse=0xF,0          // write formatted string to stdout

const section read ip                            // read-only data section
// Text strings:

text1: int8 "\nForwardCom test suite\nTest general purpose register arithmetic instructions"  // intro text,
       int8 "\nPress Run to continue"
       int8 "\n                  int8   int16  int32  int64", 0                               // and heading
newline: int8 "\n", 0                                                                         // newline
press_run: int8 "\nPress Run to continue", 0

format1: int8 "\n%-18s%3c%7c%7c%7c", 0           // format string for printing results

textadd: int8 "add", 0                           // text strings for each instruction
textsub: int8 "sub", 0
textmul: int8 "mul", 0

textmulhisigned: int8 "mul_hi signed", 0
textmulhiunsigned: int8 "mul_hi unsigned", 0

textdivsigned: int8 "div signed", 0
textdivunsigned: int8 "div unsigned", 0

textremsigned: int8 "rem signed", 0
textremunsigned: int8 "rem unsigned", 0

textmaxsigned: int8 "max signed", 0
textmaxunsigned: int8 "max unsigned", 0

textminsigned: int8 "min signed", 0
textminunsigned: int8 "min unsigned", 0

textcompsigned: int8 "compare signed", 0
textcompunsigned: int8 "compare unsigned", 0

textabs: int8 "abs", 0

textsignx: int8 "sign_extend", 0

textroundp2: int8 "roundp2", 0

textaddadd: int8 "add_add", 0

textmuladd: int8 "mul_add", 0

textsignexadd: int8 "sign_extend_add", 0

const end


code section execute                             // code section

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

// Test addition
int32  r1 = 0x12345678
int32  r2 = 0x9abcdef0

int8   r3 = r1 + r2                              // int8 addition
int32  r0 = r3 == ((0x78 + 0xf0) & 0xFF)         // check result, set bit 0 if success

int16  r3 = r1 + r2                              // int16 addition
int32  r4 = r3 == ((0x5678 + 0xdef0) & 0xFFFF)   // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = r1 + r2                              // int32 addition
int32  r4 = r3 == (0x12345678 + 0x9abcdef0)      // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r1 += 0x12345
int64  r3 = r1 + r2                              // 64 bit addition
int32  r4 = r3 == 0x12345                        // check lower half of result
uint64 r3 >>= 32                                 // shift down upper half
int64  r6 = (r3 == (0x12345678 + 0x9abcdef0)) && r4  // check upper half of result
int32  r0 |= 8, mask = r6                        // set bit 2 if success

int64  r1 = address [textadd]
call   print_result


// Test subtraction
int32  r1 = 0x12345678
int32  r2 = 0x9abcdef0

int8   r3 = r1 - r2                              // int8 addition
int32  r0 = r3 == ((0x78 - 0xf0) & 0xFF)         // check result, set bit 0 if success

int16  r3 = r1 - r2                              // int16 addition
int32  r4 = r3 == ((0x5678 - 0xdef0) & 0xFFFF)   // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = r1 - r2                              // int32 addition
int32  r4 = r3 == ((0x12345678 - 0x9abcdef0) & 0xFFFFFFFF) // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r1 += 0x12345
int64  r3 = r1 - r2                              // 64 bit addition
int64  r4 = ((0x12345678 - 0x9abcdef0) << 32) + 0x12345
int64  r5 = r3 == r4 && r6
int32  r0 |= 8, mask = r5                        // set bit 2 if success

int64  r1 = address [textsub]
call   print_result


// Test multiplication
int32 r1 = 0x12345678
int32 r2 = 0x9abcdef0

int8   r3 = r1 * r2                              // int8 multiplication
int32  r0 = r3 == ((0x78 * 0xf0) & 0xFF)         // check result, set bit 0 if success

int16  r3 = r1 * r2                              // int16 multiplication
int32  r4 = r3 == ((0x5678 * 0xdef0) & 0xFFFF)   // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = r1 * r2                              // int32 multiplication
int32  r4 = r3 == ((0x12345678 * 0x9abcdef0) & 0xFFFFFFFF) // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

if (int r6 & 1) {                                // try only if 64 bits supported
    int64  r1 <<= 32
    int64  r2 <<= 32
    int64  r1 += 0x00012345
    int64  r2 += 0x6edc4321
    int64  r3 = r1 * r2                          // 64 bit multiplication
    int64  r4 = (0x1234567800012345 * 0x9abcdef06edc4321) // expected result
    int64  r5 = (r3 == r4)
    int32  r0 |= 8, mask = r5                    // set bit 2 if success
}

int64  r1 = address [textmul]
call   print_result


// Test mul_hi: high part of product, signed
int32  r1 = 0xa1b2c3d4
int32  r2 = 0xe5f60718

int8   r3 = mul_hi(r1, r2)
int32  r0 = r3 == ((0xffd4 * 0x18) >> 8 & 0xFF)   // check result, set bit 0 if success

int16  r3 = mul_hi(r1, r2)
int32  r4 = r3 == ((0xffffc3d4 * 0x0718) >> 16 & 0xFFFF) // check result, set bit 0 if success
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = mul_hi(r1, r2)
int32  r4 = r3 == ((0xffffffffa1b2c3d4 * 0xffffffffe5f60718) >> 32 & 0xFFFFFFFF) // check result, set bit 0 if success
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 = 0x21b2c3d4e5f60718
int64  r2 = 0x46352958adbecef8
%prodhi = (((0xe5f60718 * 0xadbecef8 >>> 32) + 0x21b2c3d4 * 0xadbecef8 + 0x46352958 * 0xe5f60718) >>> 32) + 0x21b2c3d4 * 0x46352958

int64  r3 = mul_hi(r1, r2)
int64  r4 = r3 == prodhi                         // check result, set bit 0 if success
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textmulhisigned]
call   print_result


// Test mul_hi: high part of product, unsigned
int32  r1 = 0xa1b2c3d4
int32  r2 = 0xe5f60718

int8   r3 = mul_hi_u(r1, r2)
int32  r0 = r3 == ((0xd4 * 0x18) >> 8 & 0xFF)   // check result, set bit 0 if success

int16  r3 = mul_hi_u(r1, r2)
int32  r4 = r3 == ((0xc3d4 * 0x0718) >> 16 & 0xFFFF) // check result, set bit 0 if success
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = mul_hi_u(r1, r2)
int32  r4 = r3 == ((0xa1b2c3d4 * 0xe5f60718) >> 32 & 0xFFFFFFFF) // check result, set bit 0 if success
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 = 0x21b2c3d4e5f60718
int64  r2 = 0x46352958adbecef8
%prodhi = (((0xe5f60718 * 0xadbecef8 >>> 32) + 0x21b2c3d4 * 0xadbecef8 + 0x46352958 * 0xe5f60718) >>> 32) + 0x21b2c3d4 * 0x46352958

int64  r3 = mul_hi_u(r1, r2)
int64  r4 = r3 == prodhi                         // check result, set bit 0 if success
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textmulhiunsigned]
call   print_result


// Test signed division
int32  r1 = 0x12345678
int32  r2 = 0xab1d2f

int8   r3 = r1 / r2                              // int8 division
int32  r0 = r3 == ((0x78 / 0x2f) & 0xFF)         // check result, set bit 0 if success

int16  r3 = r1 / r2                              // int16 division
int32  r4 = r3 == ((0x5678 / 0x1d2f) & 0xFFFF)   // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = r1 / r2                              // int32 division
int32  r4 = r3 == ((0x12345678 / 0xab1d2f) & 0xFFFFFFFF) // check result

int32  r6 = -r2
int32  r3 = r1 / r6                              // int32 division negative
int32  r5 = r3 == (-(0x12345678 / 0xab1d2f) & 0xFFFFFFFF) // check result
int    r4 &= r5
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r1 |= 0x22334455
int64  r2 |= 0x66778899

int64  r3 = r1 / r2
int32  r4 = r3 == 0x1234567822334455 / 0xab1d2f66778899 // check result
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textdivsigned]
call   print_result


// Test unsigned division
int32  r1 = 0x12345678
int32  r2 = 0xffabf2f3

uint8  r3 = r1 / r2                              // int8 unsigned division
int    r0 = r3 == 0                              // check result, set bit 0 if success
uint8  r3 = r2 / r1                              // int8 unsigned division
int    r0 = r3 == 2 && r0                        // check result, set bit 0 if success

uint16 r3 = r1 / r2                              // int16 unsigned division
int32  r5 = r3 == 0                              // check result, set bit 0 if success
uint16 r3 = r2 / r1                              // int16 unsigned division
int32  r4 = r3 == 2 && r5
int    r0 |= 2, mask = r4                        // set bit 1 if success

uint32 r3 = r1 / r2                              // int32 unsigned division
int32  r5 = r3 == 0                              // check result, set bit 0 if success
uint32 r3 = r2 / r1                              // int32 unsigned division
int32  r4 = r3 == 0xE                            // check result, set bit 0 if success
int    r4 &= r5
int    r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r1 |= 0x22334455
int64  r2 |= 0x66778899
uint64 r3 = r2 / r1
int64  r4 = r3 == 0xffabf2f3 / 0x12345678
int    r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textdivunsigned]
call   print_result


// Test rem, signed
%A = 0xcc5d8e9f
%B = 0x1c1d1e18

int32 r1 = A
int32 r2 = B

int8   r3 = r1 % r2                              // int8 modulo
int32  r0 = r3 == (-((-A & 0xFF) % (B & 0xFF)) & 0xFF) // check result, set bit 0 if success

int16  r3 = r1 % r2                              // int16 modulo
int32  r4 = r3 == (-((-A & 0xFFFF) % (B & 0xFFFF)) & 0xFFFF) // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = r1 % r2                              // int32 modulo
int32  r4 = r3 ==(-((-A & 0xFFFFFFFF) % (B & 0xFFFFFFFF)) & 0xFFFFFFFF) // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r1 |= r2
int64  r2 <<= 32

%A1 = (A << 32) + A
int64 r1 = A1
int64 r2 = B
int64  r3 = r1 % r2                              // int64 modulo
%modulo1 = -(-A1 % B)
int64  r4 = r3 == modulo1                        // check result
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textremsigned]
call   print_result


// Test rem, unsigned
int32  r1 = A
int32  r2 = B

uint8  r3 = r1 % r2                              // int8 modulo
int32  r0 = r3 == (A & 0xFF) % (B & 0xFF)        // check result, set bit 0 if success

uint16 r3 = r1 % r2                              // int16 modulo
int32  r4 = r3 == (A & 0xFFFF) % (B & 0xFFFF)    // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

uint32 r3 = r1 % r2                              // int32 modulo
int32  r4 = r3 == (A & 0xFFFFFFFF) % (B & 0xFFFFFFFF) // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 = A1
uint64 r3 = r1 % r2                              // int64 modulo
%modulo1 = 0x177FFA97
int64  r4 = r3 == modulo1                        // check result
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textremunsigned]
call   print_result


int64  r0 = address [press_run]                  // press run to continue
call   _printf                                   // print string

breakpoint


// Test max signed
int32  r1 = A
int32  r2 = B

int8   r3 = max(r1, r2)                          // int8 max
int32  r0 = r3 == (B & 0xFF)                     // check result, set bit 0 if success

int16  r3 = max(r1, r2)                          // int16 max
int32  r4 = r3 == (B & 0xFFFF)                   // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = max(r2, r1)                          // int32 max
int32  r4 = r3 == (B & 0xFFFFFFFF)               // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r3 = max(r1, r2)                          // int64 max
int64  r3 >>= 32
int64  r4 = r3 == B                              // check result

int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textmaxsigned]
call   print_result


// Test max unsigned
int32 r1 = A
int32 r2 = B

uint8  r3 = max(r1, r2)                          // int8 max
int32  r0 = r3 == (A & 0xFF)                     // check result, set bit 0 if success

uint16 r3 = max(r1, r2)                          // int16 max
int32  r4 = r3 == (A & 0xFFFF)                   // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

uint32 r3 = max(r2, r1)                          // int32 max
int32  r4 = r3 == (A & 0xFFFFFFFF)               // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
uint64 r3 = max(r1, r2)                          // int64 max
uint64 r3 >>= 32
int64  r4 = r3 == A                              // check result
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textmaxunsigned]
call   print_result


// Test min signed
int32 r1 = A
int32 r2 = B

int8   r3 = min(r1, r2)                          // int8 max
int32  r0 = r3 == (A & 0xFF)                     // check result, set bit 0 if success

int16  r3 = min(r1, r2)                          // int16 max
int32  r4 = r3 == (A & 0xFFFF)                   // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

int32  r3 = min(r2, r1)                          // int32 max
int32  r4 = r3 == (A & 0xFFFFFFFF)               // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r3 = min(r1, r2)                          // int64 max
int64  r3 >>= 32
int64  r4 = r3 == A - (1 << 32)                  // check result
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textminsigned]
call   print_result


// Test min unsigned
int32  r1 = A
int32  r2 = B

uint8  r3 = min(r1, r2)                          // int8 max
int32  r0 = r3 == (B & 0xFF)                     // check result, set bit 0 if success

uint16 r3 = min(r1, r2)                          // int16 max
int32  r4 = r3 == (B & 0xFFFF)                   // check result
int32  r0 |= 2, mask = r4                        // set bit 1 if success

uint32 r3 = min(r2, r1)                          // int32 max
int32  r4 = r3 == (B & 0xFFFFFFFF)               // check result
int32  r0 |= 4, mask = r4                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
uint64 r3 = min(r1, r2)                          // int64 max
uint64 r3 >>= 32
int64  r4 = r3 == B                              // check result
int32  r0 |= 8, mask = r4                        // set bit 3 if success

int64  r1 = address [textminunsigned]
call   print_result


// Test compare signed
int32  r1 = A
int32  r2 = B

int8   r0 = r1 < r2                              // int8 compare
int8   r0 = r2 > r1 && r0                        // int8 compare && last result

int16  r3 = r1 <= r2                             // int16 compare
int16  r3 = r1 != r2 && r3                       // int16 compare
int    r0 |= 2, mask = r3                        // set bit 1 if success

int32  r3 = r1 <= r2                             // int32 compare
int32  r3 = r2 >= r1 && r3                       // int32 compare
int32  r0 |= 4, mask = r3                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
int64  r3 = r1 < r2                              // int64 compare
int64  r3 = r2 > r1 && r3                        // int64 compare
int64  r3 = r2 == r2 && r3                       // int64 compare
int64  r0 |= 8, mask = r3                        // set bit 3 if success

int64  r1 = address [textcompsigned]
call   print_result


// Test compare unsigned
int32  r1 = A
int32  r2 = B

uint8  r0 = r1 > r2                              // int8 compare
uint8  r0 = r2 < r1 && r0                        // int8 compare && last result

uint16 r3 = r1 >= r2                             // int16 compare
uint16 r3 = r1 != r2 && r3                       // int16 compare
int    r0 |= 2, mask = r3                        // set bit 1 if success

uint32 r3 = r1 >= r2                             // int32 compare
uint32 r3 = r2 <= r1 && r3                       // int32 compare
int32  r0 |= 4, mask = r3                        // set bit 2 if success

int64  r1 <<= 32
int64  r2 <<= 32
uint64 r3 = r1 > r2                              // int64 compare
uint64 r3 = r2 < r1 && r3                        // int64 compare
uint64 r3 = r2 == r2 && r3                       // int64 compare
int64  r0 |= 8, mask = r3                        // set bit 3 if success

int64  r1 = address [textcompunsigned]
call   print_result


// Test abs
int8   r1 = -20
int8   r3 = abs(r1, 0)                           // int8 abs
int    r0 = r3 == 20
int8   r1 = 0x80
int8   r3 = abs(r1, 0)                           // overflow wrap around
int    r0 = r3 == r1 && r0
int8   r3 = abs(r1, 1)                           // overflow saturates
int    r0 = r3 == 0x7F && r0
int8   r3 = abs(r1, 2)                           // overflow gives zero
int    r0 = r3 == 0 && r0

int16  r1 = 0x7fff
int16  r2 = abs(r1,0)                            // int16 abs
int    r3 = r2 == r1
int16  r2 = r1 + 1                               // 0x8000
int16  r2 = abs(r2, 1)                           // overflow saturates
int    r3 = r2 == r1 && r3
int    r0 |= 2, mask = r3                        // set bit 1 if success

int32  r1 = 0x7fffffff
int32  r2 = abs(r1, 0)                           // int32 abs
int    r3 = r2 == r1
int32  r2 = r1 + 1                               // 0x80000000
int32  r2 = abs(r2, 1)                           // overflow saturates
int    r3 = r2 == r1 && r3
int    r0 |= 4, mask = r3                        // set bit 2 if success

int64  r1 = -12345 - (1 << 40)
int64  r2 = abs(r1, 0)                           // int64 abs
int64  r3 = r2 == 12345 + (1 << 40)
int64  r2 >>= 32
int32  r3 = r2 == 1 << 8 && r3
int    r0 |= 8, mask = r3                        // set bit 3 if success

int64  r1 = address [textabs]
call   print_result


// Test sign_extend
int32  r1 = 0x1234fe
int8   r2 = sign_extend(r1)                      // sign extend from 8 bits to 64 bits
int64  r0 = r2 == -2
int16  r2 = sign_extend(r1)                      // sign extend from 16 bits to 64 bits
int64  r3 = r2 == 0x34fe
int16  r2 = sign_extend(-20)                     // sign extend from 16 bits to 64 bits
int64  r3 = (r2 == -20) && r3
int    r0 |= 2, mask = r3                        // set bit 1 if success
int32  r1 = -r1
int32  r2 = sign_extend(r1)                      // sign extend from 32 bits to 64 bits
int64  r3 = r2 == -0x1234fe
int    r0 |= 4, mask = r3                        // set bit 2 if success
int    r0 |= 1 << 7                              // suppress 'N' for 64 bits

int64  r1 = address [textsignx]
call   print_result


// Test roundp2
int32  r1 = 0x1234fe
int8   r2 = roundp2(r1, 0)                       // 8 bit round down to power of 2
int    r0 = r2 == 0x80
int8   r2 = roundp2(r1, 0x21)                    // 8 bit round up to power of 2
int8   r0 = (r2 == -1) && r0                     // overflow

int16  r2 = roundp2(r1, 0)                       // 16 bit round down to power of 2
int    r3 = r2 == 0x2000
int16  r2 = roundp2(r1, 1)                       // 16 bit round up to power of 2
int    r3 = (r2 == 0x4000) && r3
int    r0 |= 2, mask = r3                        // set bit 1 if success

int32  r2 = roundp2(r1, 0)                       // 32 bit round down to power of 2
int32  r3 = r2 == 0x100000
int32  r2 = roundp2(r1, 1)                       // 32 bit round up to power of 2
int32  r3 = (r2 == 0x200000) && r3
int32  r1 <<= 11
int32  r2 = roundp2(r1, 1)                       // 32 bit round up overflow
int32  r3 = (r2 == 0) && r3
int32  r2 = roundp2(r2, 0x10)                    // 32 bit down zero
int32  r3 = (r2 == -1) && r3
int    r0 |= 4, mask = r3                        // set bit 2 if success

int64  r2 = roundp2(r1, 0)                       // 64 bit round down to power of 2
uint64 r3 = r2 == 0x80000000
int64  r2 = roundp2(r1, 1)                       // 64 bit round up to power of 2
int64  r2 >>= 32
int64  r3 = r2 == 1 && r3
int    r0 |= 8, mask = r3                        // set bit 3 if success

int64  r1 = address [textroundp2]
call   print_result


// Test add_add
%A = 0xcc5d8e9f
%B = 0x1c1d1e18
%C = 0x538e0c17

int r1 = A
int r2 = B
int r3 = C

int8   r4 = r1 + r2 + r3                         // int8 add_add
int    r0 = r4 == (A + B + C & 0xFF)

int16  r4 = -r1 + r2 + r3                        // int16 add_add
int    r5 = r4 == (- A + B + C & 0xFFFF)
int    r0 |= 2, mask = r5                        // set bit 1 if success

int32  r4 = r1 - r2 + r3                         // int32 add_add
int    r5 = r4 == (A - B + C & 0xFFFFFFFF)
int    r0 |= 4, mask = r5                        // set bit 2 if success

int64  r2 <<= 32
int64  r4 = r1 + r2 - r3                         // int64 add_add
int64  r5 = r4 == A + (B << 32) - C 
int64  r4 >>= 32
int32  r5 = r4 == (A - C >> 32) + B && r5
int    r0 |= 8, mask = r5                        // set bit 3 if success

int64  r1 = address [textaddadd]
call   print_result


// Test mul_add
int r1 = A
int r2 = B
int r3 = C

int8   r4 = r1 * r2 + r3                         // int8 mul_add
int    r0 = r4 == ((A * B + C) & 0xFF)

int16  r4 = -r1 * r2 + r3                        // int16 mul_add
int    r5 = r4 == (-A * B + C & 0xFFFF)
int    r0 |= 2, mask = r5                        // set bit 1 if success

int32  r4 = r1 * 1234 - r3                       // int32 mul_add2
int    r5 = r4 == (A * 1234 - C & 0xFFFFFFFF )
int    r0 |= 4, mask = r5                        // set bit 2 if success

int64  r2 <<= 32
int64  r4 = r1 * r2 - (123 << 32)                // int64 mul_add
uint64 r4 >>= 32
int64  r5 = r4 == ((A * B - 123) & 0xFFFFFFFF)

int    r0 |= 8, mask = r5                        // set bit 3 if success

int64  r1 = address [textmuladd]
call   print_result


// Test sign_extend_add
int r1 = A
int r2 = B

int8   r4 = sign_extend_add(r2, r1)
int64  r0 = r4 == B + (A & 0xFF) - 0x100

int16  r4 = sign_extend_add(r2, r1), options = 2
int64  r5 = r4 == B + ((A & 0xFFFF) << 2) - (0x10000 << 2)
int    r0 |= 2, mask = r5                        // set bit 1 if success

int32  r4 = sign_extend_add(r1, r2), options = 3
int64  r5 = r4 == A + ((B & 0xFFFFFFFF) << 3) // - (0x100000000 << 3)
int    r0 |= 4, mask = r5                        // set bit 2 if success

int64  r4 = sign_extend_add(r2, r1), options = 3
int64  r5 = r4 == B + (A << 3)
uint64 r4 >>= 3
int32  r5 = r4 == (B >> 3) + A && r5
int    r0 |= 8, mask = r5                        // set bit 3 if success


int64  r1 = address [textsignexadd]
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