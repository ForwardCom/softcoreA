/*************************  testpushpop.as  ***********************************
* Author:        Agner Fog
* date created:  2022-12-17
* last modified: 2022-12-17
* Version:       1.12
* Project:       ForwardCom test, assembly code
* Description:   Tests ForwardCom hardware implementation.
*
* This code tests push and pop instructions
*
* Link with library libc_light.li
*
* Copyright 2022 GNU General Public License http://www.gnu.org/licenses
*****************************************************************************/

extern _printf: function                         // library function: formatted output to stdout
extern _puts:   function                         // write string + linefeed to stdout


const section read ip                            // read-only data section
// Text strings:

intro: int8 "\nForwardCom test suite\nTest mul and div instructions"  // intro text,
       int8 "\nPress Run to continue\n", 0
       int8 "\n                          int8   int16  int32  int64", 0          // and heading
newline: int8 "\n", 0                                                            // newline
press_run: int8 "\nPress Run to continue", 0
finished: int8 "\nFinished", 0
failure: int8 "\nError code %i", 0

const end

code section execute align = 4                   // code section

_main function public                            // program begins here
int64 r0 = address [press_run]
call _puts
breakpoint                                       // user must press run to continue if running on hardware

// arbitrary test values
int64 r1 = -1
int64 r2 = 0x123456789ABCDEF0
int64 r3 = 0x3333333333333333
int64 r4 = 0x4444444444444444
int64 r5 = 0x5555555555555555


// 1. 64 bit push and pop with multiple registers and different stack pointers
int64 r10 = sp
push (r2)
pop (r2)

push (r1)
push (r2,4)
int64 r11 = r10 - sp
pop (r4)
pop (r1,3)
int64 r30 = sp != r10
int64 r30 = r11 != 4*8 || r30

int64 r20 = sp - 0x100
int32 push(r20, r1, 3)
int32 pop(r20, r11, 13)
int64 r11 += r12 + r13
int64 r11 -= 0x1CDF01222
int64 r30 |= r11

int r0 = 1
if (int64 r30 != 0) {call error_report} 
nop


// 2. 32 bit push and pop in FILO mode
int64 r20 = sp - 0x100
int32 push(r20, r1, 3 | 0x80)
int64 r21 = sp - 0x100
int32 pop(r21, r11, (13 + 0x40))
int64 r15 = r20 - r21
int64 r20 -= 3*4
int32 r13 = [r20+4]
int32 r30 = r13 != r2

// 16 bit push and pop in FIFO mode
int64 r20 = sp
int16 push(r1, 4)
int64 r15 = r20-sp
int16 pop(r11, 14)
int32 r30 = sp != r20 || r30
int16 r22 = r2
int32 r30 = r12 != r22 || r30
nop

// 8 bit push and pop in FIFO mode
int64 r20 = sp
int8 push(r1, 4)
int64 r15 = r20-sp
int8 pop(r11, 14)
int64 r16 = r15 - 4
int32 r30 |= r16
int32 r17 = [r20-4]
int8  r18 = r17 - r4
int32 r30 |= r18
nop
int r0 = 2
if (int64 r30 != 0) {call error_report} 
nop


// 3. 32 bit push waiting for operand
int32 r6 = r3 * 3
int32 push(r4, 6)
int32 pop(r14, 16)
int32 r30 = r16 != r6
int r0 = 3
if (int64 r30 != 0) {call error_report} 
nop


// finished. print text
int64  r0 = address [finished]  
call   _puts                   // write text

breakpoint

return
_main end


error_report function public                     // print error code in r0
// set up parameter list for printf
int64 sp -= 8                // allocate space on stack
int64 [sp] = r0              // parameter
int64 r0 = address [failure] // format string
int64 r1 = sp                // pointer to variable argument list
call _printf
int64 sp += 8                // release stack space

error_report end
return

code end