/*************************  test_muldiv.as  ***********************************
* Author:        Agner Fog
* date created:  2022-11-27
* last modified: 2022-12-05
* Version:       1.12
* Project:       ForwardCom test, assembly code
* Description:   Tests ForwardCom hardware implementation.
*
* This code tests multiplication and division, including
* mul, mul_add, mul_add2, mul_hi, mul_hi_u, 
* div, div_u, div_rev, div_rev_u, rem, rem_u
*
* Link with library libc.li
*
* Copyright 2022 GNU General Public License http://www.gnu.org/licenses
*****************************************************************************/

extern _printf: function                         // library function: formatted output to stdout
extern _puts:   function                         // write string + linefeed to stdout


const section read ip                            // read-only data section
// Text strings:
intro: int8 "\nForwardCom test suite\nTest mul and div instructions"      // intro text,
       int8 "\nPress Run to continue\n", 0
       int8 "\n                          int8   int16  int32  int64", 0   // and heading
newline: int8 "\n", 0                                                     // newline
press_run: int8 "\nPress Run to continue", 0
finished: int8 "\nFinished", 0
failure: int8 "\nError code %i", 0
notsupport64bits: int8 "\n64 bits not supported", 0
support64bits: int8 "\n64 bits supported", 0

const end

code section execute align = 4                   // code section

_main function public                            // program begins here

int64 r0 = address [press_run]
call _puts
breakpoint                                       // user must press run to continue if running on hardware


// 1. test multiplication with different operand sizes and boundary cases
int r0 = 0
int r1 = 1
int r20 = 0
int64 r2 = 0x856FA0A387F6D8B2
int64 r3 = 0x307C521FB9564823
int8  r4 = r2 * r3
int16 r5 = r2 * r3
int32 r6 = r2 * r3
int32 r7 = r2 * r0
int32 r8 = r0 * r0
int32 r9 = r1 * r1
int32 r10 = r4 + r5 + r6
int32 r10 += r7 + r8
int32 r10 += r9
int32 r10 -= 0x717E6103
int32 r20 += r10

int32 r11 = - r1
int32 r4 = r2 * r11
int32 r5 = -1 * r11
int32 r6 = r11 * r1
int32 r10 = r4 + r5 + r6
int32 r10 += r2
int32 r20 += r10

int r0 = 1
if (int64 r20 != 0) {call error_report} 


// 2. test mul_add
int32 r4 = r2 * r3 + r1
int32 r5 = r3 * r2 - r1
int32 r6 = -r2 * r3 + 77
int32 r7 = -r2 * 500 + r3
int16 r8 = -r3 * r2 - 456
int32 r10 = r4 + r5 + r6
int32 r10 += r7 + r8
int32 r10 -= 0x9CB50B00
int32 r20 += r10
int r0 = 2
if (int64 r20 != 0) {call error_report} 


// 3. test mul_hi
int r0 = 0
int r1 = 1
int64 r11 = -1
int8  r4 = mul_hi(r2,r3)
int16 r5 = mul_hi(r2,r3)
int32 r6 = mul_hi(r3,r2)
int8  r7 = mul_hi_u(r2,r3)
int16 r8 = mul_hi_u(r2,r3)
int32 r9 = mul_hi_u(r2,r3)
int32 r10 = r4 + r5 + r6
int32 r10 += r7 + r8
int32 r10 += r9
int32 r10 -= 0x83927DDD
int32 r20 = r10

int8  r4 = mul_hi(r2,r1)
int16 r5 = mul_hi(r2,r11)
int32 r6 = mul_hi(r11,r11)
int32 r7 = mul_hi(r11,r0)
int32 r8 = mul_hi(r0,r0)
int32 r9 = mul_hi(r1,r11)
int32 r12 = mul_hi(r3,0xabcd)
int32 r10 = r4 + r5 + r6
int32 r10 += r7 + r8
int32 r10 += r9 + r12
int32 r10 -= 0xFFFFD192
int32 r20 += r10

int8  r4 = mul_hi_u(r2,r1)
int16 r5 = mul_hi_u(r2,r11)
int32 r6 = mul_hi_u(r11,r11)
int32 r7 = mul_hi_u(r11,r0)
int32 r8 = mul_hi_u(r0,r0)
int32 r9 = mul_hi_u(r1,r11)
int32 r12 = mul_hi_u(r3,0xabcd)
int32 r10 = r4 + r5 + r6
int32 r10 += r7 + r8
int32 r10 += r9 + r12
int32 r10 -= 0xB956E3DC
int32 r20 += r10

// test 64 bits multiplication
if (int64 r11 & 1 << 63) {
    // 64 bits supported
    int64 r4 = r2 * r3
    int64 r5 = r2 * r11
    int64 r6 = r3 * 0x12345678
    int64 r7 = r4 * r5 + 0xabcd
    int64 r8 = -r6 * 0xabcd - r2
    int64 r10 = r4 + r5 + r6
    int64 r10 += r7 + r8
    int64 r10 -= 0xB9C61F5CED535C13
    int64 r20 = r10
    
    int64 r4 = mul_hi(r2,r3)
    int64 r5 = mul_hi_u(r2,r3)
    int64 r5 = mul_hi_u(r2,r11)    
    int64 r10 = r4 + r5 + r6
    int64 r10 -= 0xD58FE73D8BB1C0B2
    int64 r20 += r10
}
    
int r0 = 3
if (int64 r20 != 0) {call error_report} 


// 10. test division with different operand sizes and boundary cases
int r0 = 0
int r1 = 1
int r20 = 0
int64 r2 = 0xD8B2856FA0A387F6
int64 r3 = 0x21FB9564307C5823
int8  r4 = r2 / r3
int16 r5 = r2 / r3
int32 r6 = r2 / r3
uint8  r7 = r2 / r3
uint16 r8 = r2 / r3
uint32 r9 = r2 / r3
int r20 = r4 + r5 + r6
int r21 = r7 + r8 + r9
int r20 += r21
int8 r10 = r3 / r2
int16 r11 = r3 / r2
int32 r12 = r3 / r2
int r10 = r10 + r11 + r12
int r20 += r10
int8 r10 = r1 / r2
int16 r11 = r1 / r2
int32 r12 = r1 / r2
int r10 = r10 + r11 + r12
int r20 += r10

int32 r13 = r1 / r1, options = 1
int32 r14 = r0 / r1, options = 1
int32 r15 = r1 / r0, options = 1
int32 r16 = r0 / r0
uint32 r17 = r0 / r0
uint8 r18 = r0 / r0
int r10 = r13 + r14 + r15
int r10 = r10 + r16 + r17
int r10 = r10 + r18 + 0
int r10 -= 0x10203
int r20 += r10

// division by zero
int8  r4 = r1 / r0
int16 r5 = r1 / r0
int32 r6 = r1 / r0
int r10 = r4 + r5 + r6
int r10 -= 0x8000807D
int r10 = r10 != 0
int r20 += r10

uint8  r4 = r1 / r0
uint16 r5 = r1 / r0
uint32 r6 = r1 / r0
int r10 = r4 + r5 + r6
int r10 -= 0x100FD
int r10 = r10 != 0
int r20 += r10

int8  r4 = r1 / r0
int16 r5 = r1 / r0
int32 r6 = r1 / r0
int r10 = r4 + r5 + r6
int r10 -= 0x8000807D
int r10 = r10 != 0
int r20 += r10

int64 r11 = -1
int8  r4 = r11 / r0
int16 r5 = r11 / r0
int32 r6 = -1 / r0
int r10 = r4 + r5 + r6
int r10 -= 0x80008080
int r10 = r10 != 0
int r20 += r10

int8 r5 = r1 / r11
uint16 r6 = r1 / r11, options = 1
uint8 r7 = r11 / r1, options = 2
uint16 r8 =  r11 / r1, options = 3
uint32 r9 =  r11 / r1
int r10 = r5 + r6 + r7
int r10 += r8 + r9
int r10 -= 0x101FC
int r20 += r10

int r5 = 0x80
int r6 = 0x8000
uint32 r7 = 0x80000000
int8 r5 /= r11
int16 r6 /= r11
int32 r7 /= r11
int32 r10 = r5 + r6 + r7
int32 r10 -= 0x80008080
int r20 += r10
nop

if (int64 r11 & 1<<63) {
    // 64 bits supported
    int64 r10 = r2 / r3
    uint64 r11 = r2 / r3
    uint64 r12 = r3 / r2
    uint64 r8 = 1 << 63
    int64 r13 = r8 / -1
    uint64 r10 += r13 - r8
    uint64 r10 += r11 + r12    
    int64 r10 -= 5
    uint64 r20 += r10
    
    // division by zero
    int64 r4 = r1 / r0
    int64 r5 = -1 / r0
    uint64 r5 >>= 1
    uint64 r6 = r1 / r0
    int64 r10 = r4 + r5 + r6
    int64 r10 -= 0xBFFFFFFFFFFFFFFE
    uint64 r20 += r10
}

int r0 = 10
if (int64 r20 != 0) {call error_report} 


// 11. test rounding mode 0: truncate
int r16 = 16
int r1 = 47 / r16, options = 0
int r2 = 48 / r16, options = 0
int r3 = 49 / r16, options = 0
int r4 = 55 / r16, options = 0
int r5 = 56 / r16, options = 0
int r6 = 57 / r16, options = 0
int r7 = -55 / r16, options = 0
int r8 = -57 / r16, options = 0
int r1 = 1
int r9 = -57 / r1, options = 0
uint r10 = -57 / r16, options = 0
uint r11 = r9 / r16, options = 0
int r20 = r1 + r2
int r3 <<= 1
int r4 <<= 2
int r5 <<= 3
int r6 <<= 4
int r7 <<= 5
int r20 += r3 + r4
int r20 += r5 + r6
int r20 += r7 + r8
int r20 += r9 + r10
int r20 += r11
int r20 -= 0x1FFFFFBA
int r0 = 11
if (int r20 != 0) {call error_report}


// 12. test rounding mode 1: floor
int r1 = 47 / r16, options = 1
int r2 = 48 / r16, options = 1
int r3 = 49 / r16, options = 1
int r4 = 55 / r16, options = 1
int r5 = 56 / r16, options = 1
int r6 = 57 / r16, options = 1
int r7 = -55 / r16, options = 1
int r8 = -57 / r16, options = 1
nop
int r1 = 1
int r9 = -57 / r1, options = 1
uint r10 = -57 / r16, options = 1
int r20 = r1 + r2
int r3 <<= 1
int r4 <<= 2
int r5 <<= 3
int r6 <<= 4
int r7 <<= 5
int r20 += r3 + r4
int r20 += r5 + r6
int r20 += r7 + r8
int r20 += r9 + r10
int r20 -= 0xFFFFF9D
int r0 = 12
if (int r20 != 0) {call error_report}


// 13. test rounding mode 2: ceil
int r1 = 47 / r16, options = 2
int r2 = 48 / r16, options = 2
int r3 = 49 / r16, options = 2
int r4 = 55 / r16, options = 2
int r5 = 56 / r16, options = 2
int r6 = 57 / r16, options = 2
int r7 = -55 / r16, options = 2
int r8 = -57 / r16, options = 2
nop
int r1 = 1
nop
int r9 = -57 / r1, options = 2
uint r10 = -57 / r16, options = 2
int r20 = r1 + r2
int r3 <<= 1
int r4 <<= 2
int r5 <<= 3
int r6 <<= 4
int r7 <<= 5
int r20 += r3 + r4
int r20 += r5 + r6
int r20 += r7 + r8
int r20 += r9 + r10
int r20 -= 0xFFFFFDD
int r0 = 13
if (int r20 != 0) {call error_report}


// 14. test rounding mode 3: round to nearest or even
int r1 = 47 / r16, options = 3
int r2 = 48 / r16, options = 3
int r3 = 49 / r16, options = 3
int r4 = 55 / r16, options = 3
int r5 = 56 / r16, options = 3
int r6 = 57 / r16, options = 3
int r7 = -55 / r16, options = 3
int r8 = -57 / r16, options = 3
int r1 = 1
int r9 = -57 / r1, options = 3
uint r10 = -57 / r16, options = 3
int r20 = r1 + r2
int r3 <<= 1
int r4 <<= 2
int r5 <<= 3
int r6 <<= 4
int r7 <<= 5
int r20 += r3 + r4
int r20 += r5 + r6
int r20 += r7 + r8
int r20 += r9 + r10
int r20 -= 0xFFFFFD5
int r0 = 14
if (int r20 != 0) {call error_report}


// 20. test rem
int r0 = 0
int r1 = 1
int r20 = 0
int64 r2 = 0xC57E33F1E17AB2C3
int64 r3 = 0x35EF57C214509714
int8 r4 = r2 % r3
uint8 r5 = r2 % r3
int16 r6 = r3 % r2
uint16 r7 = r3 % r2
int32 r8 = r2 % r3
uint32 r9 = r2 % r3
int32 r10 = r4 + r5 + r6
int32 r10 += r7 + r8
int32 r10 += r9
int32 r10 -= 0xF7D0FB31
int32 r20 += r10

int32 r4 = r2 % 100
int32 r5 = r2 % -100
int32 r6 = r2 / 100
int32 r6 = r2 - r6 * 100
int32 r7 = r2 / -100
int32 r7 = r2 + r7 * 100
int32 r10 = r4 - r6
int32 r10 += r5 - r7
int32 r20 += r10

int8 r4 = r1 % r0
uint8 r5 = r1 % r0
int16 r6 = r2 % r0
uint16 r7 = r2 % r0
int32 r8 = r1 % r0
uint32 r9 = r1 % r0
int32 r11 = r0 % r0
int32 r10 = r4 + r5 + r6
int32 r10 += r7 + r8
int32 r10 += r9 + r11
int32 r10 -= 0x1658A
int32 r20 += r10

int32 r4 = r2 % r1
uint32 r5 = r2 % r1
int32 r6 = r1 % r1
int32 r7 = r2 % 2
uint32 r8 = r2 % 2
uint32 r9 = r2 % -1
uint32 r9 -= r2
int32 r10 = r4 + r5 + r6
int32 r10 += r7 + r8
int32 r10 += r9
int32 r20 += r10
int64 r4 = -1

if (int64 r4 & 1<<63) {
    // 64 bits supported
    int64 r5 = r2 % r3
    int64 r6 = r3 % r2
    uint64 r7 = r2 % r3
    uint64 r8 = r3 % r2
    int64 r9 = r4 % r4
    int64 r10 = r5 + r6 + r7
    int64 r10 += r8 + r9
    int64 r10 -= 0x8AFC67E3C2F56586
    int64 r20 += r10
}    
int r0 = 20
if (int64 r20 != 0) {call error_report} 


// tell if 64 bits supported:
int64  r0 = address [notsupport64bits]
int64 r9 = -1
if (int64 r9 & 1 << 63) {
    int64 r0 += support64bits - notsupport64bits
}
call   _puts                   // write text

// print final text
int64  r0 = address [finished]  
call   _puts                   // write text

breakpoint

return
_main end


// print error code in r0
error_report function public
// set up parameter list for printf
int64 sp -= 8                // allocate space on stack
int64 [sp] = r0              // parameter
int64 r0 = address [failure] // format string
int64 r1 = sp                // pointer to variable argument list
call _printf
int64 sp += 8                // release stack space
return
error_report end





code end