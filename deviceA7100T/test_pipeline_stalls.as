/*************************  test_pipeline_stalls.as  *************************
* Author:        Agner Fog
* date created:  2022-11-27
* last modified: 2022-12-05
* Version:       1.12
* Project:       ForwardCom test, assembly code
* Description:   Tests ForwardCom hardware implementation.
*
* This code tests different kinds of pipeline stalls to see if they are
* handled correctly and if operands are sampled at the right times.
*
* Link with library libc.li
*
* Copyright 2022 GNU General Public License http://www.gnu.org/licenses
*****************************************************************************/

// Library functions in libc_light.li
extern _printf: function                         // library function: formatted output to stdout
extern _puts:   function                         // write string + linefeed to stdout

const section read ip                            // read-only data section
// Text strings:
press_run: int8 "\nPress Run to continue", 0
success:   int8 "\nFinished successfully", 0
failure:   int8 "\nFailed!", 0
error:     int8 "\nError code %i", 0
const end


code section execute align = 4                   // code section

_main function public                            // program begins here

int64 r0 = address [press_run]
call _puts                                       // press run to continue
breakpoint


// 1. test memory read during pipeline stall. must sample value in the right clock cycle
int r0 = 77
int r1 = 0x123
int r2 = 0x45678
int r3 = 0xcd
int [sp-16] = r2
int [sp-8] = 0x88
int r4 = r3 * r1
    nop
    nop
    nop
int r7 = [sp-8] + r4 
int r9 = [sp-16]
int r8 = r7 + r9
int r4 = r2*r3
int r7 = [sp-8] + r4 
int r9 = [sp-16]
int r6 = [sp-8] + r9
int r8 += r6 + r7
int r20 = r8 - 0x382D5A7

// stall after multiplication
int r4 = r3 * [sp-8]
int r5 = r3 * r2 + 6
int r6 = r3 * r1 - r2
int r7 = r6 * 9 + r5
int r8 = r6 + r7
int r8 -= 0x356F7B4
int r20 += r8

// division after branch bubble
int r8 = 0
int [sp-16] = r2
int r10 = sp - 16
int r1 = [r10]
if (int r1 != r2) {
    int r8++
}
int r4 = r1 / 3
int r5 = r1 / 5
if (int r4 != r5) {
    int r8++
}
int r8 += r4 + r5
int r8 -= 0x25041
int r20 += r8
int r21 = r20

int r0 = 1
if (int64 r20 != 0) {call error_report} 


// 2. test possible spill-over of temporary register values from a preceding 
// stalled instruction in the address generator during pipeline bubbles:

int64 sp -= 32
int r9 = 8
int r12 = 9
int [sp+0x00] = r9
int [sp+0x08] = r12
int r2 = r9 + r12  
int [sp+0x10] = r2
int r1 = r9 + [sp+r9]
int r8 = r1 - 0x11
int r20 = r8
int r21 += r20
int r0 = 2
if (int64 r20 != 0) {call error_report} 
nop


// 3. test division stall
int r8 = 0
uint r5 = r2 / r0
int r8 ++
int r8 ++
uint r6 = r2 / r1
int r8 += r5
uint r7 = r3 / r0
uint r9 = r2 / 0x53
int r9 = r9 / 3
int r9 = r9 * 0x17
int r8 += r9 - 10
int r20 = r8

// test division result delayed when result buffer 2 is used by multiplication
int r8 = 0
uint r12 = 0x5705 / r0
int r8 += r12 * 5
int r4 = r1 * 0x51      // block result buffer 2 to delay division result
int r5 = r2 * 3
int r6 = r3 * 9
int r7 = r4 * 7
int r9 = r1 * r3
int r10 = r1 / 6
if (int r4 != r5) {
int r8++
}
int r11 = r4 + r5 + r6
int r11 += r7 + r9
int r8 += r10 + r11
int r8 -= 0x1199A
int r20 += r8
int r21 += r20
int r0 = 3
if (int64 r20 != 0) {call error_report} 
nop


// 4. more division stalls
int r0 = 0
int r1 = 0x1234
int r2 = -0x45678
int r3 = 0x100
int r4 = r1 / r3
int r5 = r1 / r1
int r6 = r3 / r1
int r7 = r1 / r0
int r8 = r2 / r0
uint r9 = r2 / r0
int r10 = r1 % r3
int r11 = r2 % r3
uint r12 = r2 % r3
int r13 = r2 % r0
uint r14 = r2 % r0
int r18 = r4 + r5 + r6
int r18 += r7 + r8
int r18 += r9 + r10
int r18 += r11 + r12
int r18 += r13 + r14
int r20 = r18 - 0xFFF75365
int r21 += r20
int r0 = 4
if (int64 r20 != 0) {call error_report} 
nop


// 5. multiplication and division masked off
int r0 = 0
int r1 = 0x1234
int r2 = -0x45678
int r3 = 0x100
int r4 = r0 ? r1 * r2 : r1
int r5 = r2 * 3
int r6 = r2 * r2
int r7 = r3 * r2
int r8 = r0 ? r3 * r2 : 0
int r9 = r3 * r2 - r7
int r10 = r0 ? r2 / r3 : r1
int r11 = r0 ? r2 / r0 : 0
int r20 = r4 + r5 + r6
int r20 += r8 + r9
int r20 += r10 + r11
int r20 -= 0xD0E7F940
int r21 += r20
int r0 = 5
if (int64 r20 != 0) {call error_report} 
nop

int r1 = r21 != 0       // true if failure
int64  r0 = address [success]
int64 r0 += failure - success, mask = r1
call   _puts                   // write text
return                                           // return from main
_main end


// print error code in r0
error_report function public
// set up parameter list for printf
int64 sp -= 8                // allocate space on stack
int64 [sp] = r0              // parameter
int64 r0 = address [error]   // format string
int64 r1 = sp                // pointer to variable argument list
call _printf
int64 sp += 8                // release stack space
return
error_report end

code end