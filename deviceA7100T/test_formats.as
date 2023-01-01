/**************************  tests_formats.as  ********************************
* Author:        Agner Fog
* date created:  2021-07-13
* last modified: 2021-08-04
* Version:       1.11
* Project:       ForwardCom Test suite, assembly code
* Description:   Test the different instruction formats
*
* This test program will test all instruction formats for general purpose 
* registers, including formats for multi-format instructions, single-format
* instructions, and jump instructions.
*
* Copyright 2021 GNU General Public License v. 3 http://www.gnu.org/licenses
******************************************************************************/

// Library functions in libc_light.li
extern _printf:   function reguse=0xF,0          // write formatted string to stdout
extern _sprintf:  function reguse=0xF,0          // write formatted string to string buffer

const section read ip                            // read-only data section

// Text strings:
introtext:    int8 "\nForwardCom test suite\nTest all instruction formats for general purpose registers."  // intro text,
              int8 "\nPress Run to continue\n", 0
newline:      int8 "\n", 0                                                                               // newline
press_run:    int8 "\nPress Run to continue", 0
multiformat:  int8 "\nMultiformat:", 0
singleformat: int8 "\nSingle format:", 0
jumpformat:   int8 "\nJump format:", 0

// format strings used by print_result
format1:      int8 "%1X%c", 0
format2:      int8 "\n%10s%6c", 0

// arbitrary test data
%T = 0x7BC30956
T1:      int32 T, T+1, T+2, T+3, T+4, T+5, T+6, T+7

const end


code1 section execute                            // code section

__entry_point function public
_main function public

// print intro text and heading
int64  r0 = address [introtext]                  // intro text
call   _printf                                   // print string

breakpoint

int64  r0 = address [multiformat]
call   _printf                                   // print string


// disable error trap for unknown instructions and array bounds violation
int    r1 = 5
int    capab2 = write_capabilities(r1, 0) 

// arbitrary test data
%A = 0x4956D5FE
%B = 0xE85B0AA1

// Test format 0.0 A  Multiformat RD = f2(RS, RT)
T00A:
int32  r20 = A
int32  r21 = B
int32  r1 = r20 + r21
int32  r0 = r1 == (A + B & 0xFFFFFFFF)
int    r1 = 0x00A
call   print_result

// Test format 0.1 B  Multiformat RD = f2(RS, IM1)
T01B:
int32  r1 = r20 + 0x59
int32  r2 = r1 ^ - 0x78
int32  r0 = r2 == ((A + 0x59 ^ -0x78) & 0xFFFFFFFF)
int    r1 = 0x01B
call   print_result

// Test format 0.8 A  Multiformat RD = f2(RD, [RS+RT*OS])
T08A:
int64  r1 = address [T1]
int    r2 = 2
int    r3 = r20
int32  r3 += [r1 + r2*4]
int32  r4 = A + T + 2
int32  r0 = r3 == r4
int    r1 = 0x08A
call   print_result

// Test format 0.9 B  Multiformat RD = f2(RD, [RS+IM1*OS])
T09B:
int64  r1 = address [T1]
int    r3 = r20
int32  r3 -= [r1 + 12]
int32  r4 = A - (T + 3)
int32  r0 = r3 == r4
int    r1 = 0x09B
call   print_result

// Test format 2.0.0 E  Multiformat RD = f2(RT, [RS+IM2])
T200E:
int64  r1 = address [T1 + 200]
int32  r3 = r20 + [r1 - 200 + 8]
int32  r4 = A + T + 2
int32  r0 = r3 == r4
int    r1 = 0x200E
call   print_result

// Test format 2.0.1 E  Multiformat RD = f2(RU, [RS+RT+IM2])
T201E:
int64  r1 = address [T1 - 200]
int    r2 = 4
int32  r3 = r20 + [r1 + r2 + 200]
int32  r4 = A + T + 1
int32  r0 = r3 == r4
int    r1 = 0x201E
call   print_result

// Test format 2.0.2 E  Multiformat RD = f2(RU, [RS+RT*OS+IM2])
T202E:
int64  r1 = address [T1 - 200]
int    r2 = 4
int32  r3 = r20 + [r1 + r2*4 + 200]
int32  r0 = r3 == A + T + 4
int    r1 = 0x202E
call   print_result

// Test format 2.0.3 E  Multiformat RD = f2(RU, [RS+RT*OS]), limit = IM2
T203E:
int64  r1 = address [T1]
int    r2 = 4
int32  r3 = r20 + [r1 + r2*4], limit = 4
int32  r0 = r3 == A + T + 4
int    r4 = read_perf(perf16, 3)                 // counter for array overflow
int    r0 = r4 == 0 && r0
int32  r3 = r20 + [r1 + r2*4], limit = 3         // exceed limit
int    r4 = read_perf(perf16, 3)                 // counter should show array overflow
int    r0 = r4 == 1 && r0
int    r4 = read_perf(perf16, 0)                 // reset counter
int    r1 = 0x203E
call   print_result

// Test format 2.0.5 E  Multiformat  RD = f3(RU, [RS+RT*OS+IM2], IM3).
T205E:
int64  r1 = address [T1]
int    r2 = 2
int32  r4 = [r1] + 0x10
int32  r0 = r4 == (T + 0x10 & 0xFFFFFFFF)
int32  r4 = [r1 + 4*r2 + 8] + 0x10
int32  r0 = r4 == (T + 4 + 0x10 & 0xFFFFFFFF) && r0
int32  r3 = B
int32  r4 = add_add(r3, [r1 + 4*r2 + 8], 0x25)
int32  r0 = r4 == (B + T + 4 + 0x25 & 0xFFFFFFFF) && r0
int    r1 = 0x205E
call   print_result

// Test format 2.0.6 E  Multiformat  RD = f3(RU, RS, RT)
T206E:
int32  r2 = 0x20000
int32  r3 = r20 + r21 - r2
int32  r0 = r3 == (A + B - 0x20000 & 0xFFFFFFFF)
int    r1 = 0x206E
call   print_result

// Test format 2.0.7 E  Multiformat  RD = f3(RS, RT, IM2 << IM3)
T207E:
int32  r3 = r20 + 0x78000000       // shifted constant
int32  r0 = r3 == (A + 0x78000000 & 0xFFFFFFFF)
int32  r3 = r20 - r21 + 0x6A00     // constant not shifted because IM3 used for options
int32  r4 = A - B + 0x6A00 & 0xFFFFFFFF
int32  r0 = r3 == r4 && r0
int    r1 = 0x207E
call   print_result

// Test format 2.1 A  Multiformat  RD = f3(RD, RT, [RS+IM2]).
T21A:
int64  r10 = address [T1 + 0x10000000]
int32  r3 = r20 - [r10 - 0x10000000]
int32  r0 = r3 == A - T
int    r1 = 0x21A
call   print_result

// Test format 2.8 A  Multiformat  RD = f3(RS, RT, IM2)
T28A:
int32  r3 = r20 - 0x12345678
int32  r0 = r3 == A - 0x12345678
int32  r3 = r20 + r21 + 0x56781234
int32  r4 = A + B + 0x56781234 & 0xFFFFFFFF
int32  r0 = r3 == r4 && r0
int    r1 = 0x28A
call   print_result


int64 r0 = address [press_run]
call _printf

breakpoint


// Test format 3.0.0 E  Multiformat  RD = f3(RU, RT, [RS+IM4])
T300E:
int32  r3 = r20 + r21 - [r10 - 0x10000000]
int32  r0 = r3 == A + B - T
int    r1 = 0x300E
call   print_result

// Test format 3.0.2 E  Multiformat  RD = f2(RU, [RS+RT*OS+IM4])
T302E:
int  r2 = 2
int32  r3 = r20 + [r10 + r2*4 - 0x10000000]
int32  r0 = r3 == A + T + 2
int    r1 = 0x302E
call   print_result

// Test format 3.0.3 E  Multiformat  RD = f2(RU, [RS+RT*OS]), limit = IM4
T303E:
int64  r1 = address [T1 - 0x400000]
int    r2 = 0x100000
int32  r3 = r20 + [r1 + r2*4], limit = 0x100000
int32  r0 = r3 == A + T
int    r4 = read_perf(perf16, 3)                 // counter for array overflow
int    r0 = r4 == 0 && r0
int32  r3 = r20 + [r1 + r2*4], limit = 0x0FFFFF  // exceed limit
int    r4 = read_perf(perf16, 3)                 // counter should show array overflow
int    r0 = r4 == 1 && r0
int    r4 = read_perf(perf16, 0)                 // reset counter
int    r1 = 0x303E
call   print_result

// Test format 3.0.5 E  Multiformat  RD = f3(RU, [RS+RT*OS+IM2], IM4)
T305E:
int64  r1 = address [T1]
int    r2 = 3
int32  r3 = [r1 + r2*4] - 0x77665544
int32  r0 = r3 == T + 3 - 0x77665544
int32  r3 = r20 - [r1 + r2*4 + 4] + 0x44556677
int32  r4 = A - (T + 4) + 0x44556677 & 0xFFFFFFFF
int32  r0 = r3 == r4 && r0
int    r1 = 0x305E
call   print_result

// Test format 3.0.7 E  Multiformat  RD = f3(RS, RT, IM4 << IM2).
T307E:
int64  r3 = r20 - 0x77665544000000
int64  r4 = A - 0x77665544000000
int64  r0 = r3 == r4
// this will report success on a CPU that supports only 32 bits because only the lower 32 bits of the result are compared
int    r1 = 0x307E
call   print_result

// Test format 3.8 A  Multiformat  RD = f3(RS, RT, IM3:IM2)
T38A:
int64  r3 = r20 + 0x123456789ABCDEF0
int64  r4 = A + 0x123456789ABCDEF0
int64  r0 = r3 == r4
// this will report success on a CPU that supports only 32 bits because only the lower 32 bits of the result are compared
int    r1 = 0x38A
call   print_result


int64 r0 = address [press_run]
call _printf

breakpoint

int64 r0 = address [singleformat]
call _printf


// format 1.0 A  Single format RD = f2(RS, RT). unused

// Test format 1.1 C  Single format RD = f2(RD, IM1-2). 32-bit instructions
T11C:
int32  r2 = -0x23AB
int32  r3 = 0x450000
int32  r2 += r3
int32  r0 = r2 == 0x450000 - 0x23AB
int32  r2 = 0XABCD
int32  r2 -= 0x5432
int32  r2 ^= 0x44000
int32  r0 = (r2 == (0XABCD - 0x5432 ^ 0x44000)) && r0
int    r1 = 0x11C
call   print_result

// Test format 1.1 C,  64-bit instructions
T111C:
int64  r2 = -0x45AB
int64  r2 += 0x340000000
int64  r4 = 0x340000000 - 0x45AB
int64  r0 = r2 == r4
int64  r2 = -0x4500000000 
int64  r2 ^= 0x5600000000000
int64  r4 = - 0x4500000000 ^ 0x5600000000000
int64  r0 = r2 == r4 && r0
int    r1 = 0x111C
call   print_result

// Test format 1.8 B  Single format RD = f2(RS, IM1)
T18B:
int32  r1 = -0x1234
int32  r2 = abs(r1, 1)
int32  r0 = r2 == 0x1234
int32  r3 = roundp2(r2,1)
int32  r0 = r3 == 0x2000 && r0
int    r1 = 0x18B
call   print_result

// Test format 2.0.6 E
T206E_s:
int32  r2 = T
int32  r3 = truth_tab3(r20, r21, r2, 0x78)
int32  r0 = r3 == (A & B ^ T)
int    r1 = 0x206E
call   print_result

// Test format 2.0.7 E
T207E_s:
int32  r1 = 7
int32  r2 = 0x12345678
int32  r3 = move_bits(r1, r2, 20, 0, 8)
int32  r0 = r3 == 0x23
int    r1 = 0x207E
call   print_result

// Test format 2.9 A
T29A:
int64  r2 = insert_hi(r20, 0xABBA)
int64  r3 = r2 + (0xCDDEF << 36)
int64  r4 = (A | 0xABBA << 32) + (0xCDDEF << 36)
int32  r0 = r3 == r4
int    r1 = 0x29A
call   print_result


int64 r0 = address [jumpformat]
call _printf


// Test format 1.6 B
T16B:
int    r1 = 1
int    r2 = 2
if (int32 r1 < r2) {int r3 = 5}
if (int32 r1 == r2) {int r3 = 6}
int32  r0 = r3 == 5
int    r1 = 0x16B
call   print_result

// Test format 1.7 C
T17C:
if (int32 r1 == 9) {int r3 = 7}
else {int r3 = 8}
int32  r0 = r3 == 8
int    r1 = 0x17C
call   print_result

// Test format 2.5.0 A
T250A:
int32  r3 = r20 + r21, jump_nzero T250A_2
int    r3 = 0
T250A_2:
int32  r0 = r3 == (A + B & 0xFFFFFFFF)
int    r1 = 0x250A
call   print_result

// Test format 2.5.1 B
T251B:
int32  r3 = r20 + 0x1000, jump_nzero T251B_2
int    r3 = 0
T251B_2:
int32  r0 = r3 == A + 0x1000
int    r1 = 0x251B
call   print_result

// Test format 2.5.2 B
options codesize = 1 << 16
T252B:
int    r3 = 0x200
int32  r3 += [T1], jump_nzero T252B_2
int    r3 = 0
T252B_2:
int32  r0 = r3 == T + 0x200
int    r1 = 0x252B
call   print_result

// Test format 2.5.4 C
options codesize = 1 << 30
T254C:
int64  r10 = address [T254C_2]
if (int32 r20 != 1) {jump TARGET1}
int    r3 = 0
T254C_2:
int32  r0 = r3 == 0x55
int    r1 = 0x254C
options codesize = 0
call   print_result

// Test format 2.5.5 C
T255C:
int32  r3 = r21
if (int32 r20 > A-1) {jump T255C_2}
int32  r3 = 0
T255C_2:
int32  r0 = r3 == r21
int    r1 = 0x255C
call   print_result

// Test format 2.5.7 C
// system call not implemented yet

// Test format 3.1.0 A
T310A:
int64  r10 = address [T310A_2]
int32  r1 = [T1]
if (int32 r1 == [T1]) {jump TARGET1}
int    r10 = 0
T310A_2:
int32  r0 = r10 != 0
int    r1 = 0x310A
call   print_result

// Test format 3.1.1 A
T311A:
int64  r10 = address [T311A_2]
if (int32 r20 == A) {jump TARGET1}
int    r10 = 0
T311A_2:
int32  r0 = r10 != 0
int    r1 = 0x311A
call   print_result


int64 r0 = address [newline]
call _printf

breakpoint

int r0 = 0                                       // program return value
return                                           // return from main

_main end


print_result function
// Print the result of a single test. Parameters:
// r0:  1 if success
// r1:  format as hexadecimal digits. e.g. 0x204E means format 2.0.4 E

// allocate space for temporary string and parameter list
int64 sp -= 64               // allocate space on stack
int    r7 = r1
int    r6 = 'N'
int    r6 = 'Y', mask = r0, fallback = r6

// find length of format name
int    r5 = 8
int    r3 = r1 >= 0x1000
int    r5 += 4, mask = r3
int64  r4 = sp + 16           // string buffer

// loop through characters in format name
for (int ; r5 >= 0; r5 -= 4) {
  // set up parameter list for sprintf
  uint32 r0 = r7 >> r5         // character
  int    r0 &= 0x0F
  int64  [sp] = r0             // part of format name
  int    r1 = ' '
  int    r3 = r5 > 4
  int    r1 = r3 ? '.' : r1    // dot or space after character
  int64  [sp+8] = r1           // character
  int64  r0 = r4               // string buffer
  int64  r1 = address [format1]// format string
  int64  r2 = sp               // parameter list
  call   _sprintf              // put part of format name in string buffer
  int64  r4 += 2               // advance string buffer pointer
}

// set up parameter list for printf
int64  r4 = sp + 16          // string buffer
int64  [sp] = r4             // format name
int64  [sp+8] = r6           // 'Y' if success
int64  r0 = address [format2]// format string
int64  r1 = sp               // parameter list
call   _printf               // write to stdout

int64 sp += 64               // free stack space
return

print_result end

code1  end


// second code section for long distance jumps
code2 section execute

TARGET1:
int    r3 = 0x55
int64  jump r10

code2  end
