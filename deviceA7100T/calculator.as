/****************************  calculator.as  *********************************
* Author:        Agner Fog
* date created:  2021-05-26
* last modified: 2022-12-12
* Version:       1.12
* Project:       ForwardCom example, assembly code
* Description:   Simple test of arithmetic instructions
*                Link with libc_light.li
*
* Copyright 2022 GNU General Public License http://www.gnu.org/licenses
*****************************************************************************/

// Library functions in libc_light.li
extern _print_string:  function reguse=3,0
extern _printf:        function reguse=0xF,0
extern _gets_s:        function reguse=3,0
extern _atoi:          function reguse=3,0
extern _multiply_int:  function reguse=1,0
extern _divide_int:    function reguse=3,0

%serial_input_status = 9               // serial input status port

const section read ip                  // read-only data section

// text strings
int8 text1 = "\nSimple calculator with two integers, a and b\n\nEnter a: \0"
int8 text2 = "\nEnter b: \0"
int8 text3 = "\nAgain (y/n)?: \0"
int8 text4 = "\nGoodbye\n\0"

// format string for printf
int8 formatstring = "\n\na     = %8i"
int8                  "\nb     = %8i"
int8                  "\na + b = %8i"
int8                  "\na - b = %8i"
int8                  "\na * b = %8i"
int8                  "\na / b = %8i"
int8                  "\na %% b = %8i\n\0"

const end


code section execute                   // code section

_main function public                  // program start

%stackframe = 64                       // size of local data
int64 sp -= stackframe                 // allocate input buffer on stack

do {                                   // repeat as long as user answers yes    

    int   r0 = 1                       // clear input buffer
    int   output(r0, r0, serial_input_status)

    int64 r0 = address([text1])
    call  _print_string                // print intro text
    int64 r0 = sp
    int   r1 = stackframe              // max. size of input buffer
    call  _gets_s                      // read a as string
    call  _atoi                        // convert to integer
    int32 r8 = r0                      // save a

    int64 r0 = address([text2])
    call  _print_string                // print Enter b
    int64 r0 = sp
    int   r1 = stackframe              // max. size of input buffer
    call  _gets_s                      // read b as string
    call  _atoi                        // convert to integer
    int32 r9 = r0                      // save b

    // set up parameter list with results
    // (reuse the input buffer as parameter list)
    int32 [sp+0x00] = r8               // a
    int32 [sp+0x08] = r9               // b
    int32 r2 = r8 + r9                 // a + b
    int32 [sp+0x10] = r2
    int32 r2 = r8 - r9                 // a - b
    int32 [sp+0x18] = r2
    //int32 r0 = r8
    //int32 r1 = r9
    //call  _multiply_int                // a * b, using function call 
    int32 r0 = r8 * r9
    int32 [sp+0x20] = r0
    //int32 r0 = r8
    //int32 r1 = r9
    //call  _divide_int                  // a / b, using function call 
    int32 r0 = r8 / r9
    int32 r1 = r8 % r9
    int32 [sp+0x28] = r0
    int32 [sp+0x30] = r1               // a % b

    // print results
    int64 r0 = address([formatstring]) // pointer to format string
    int64 r1 = sp                      // pointer to parameter list
    call  _printf                      // print results

    // ask if the user wants to try again
    int64 r0 = address([text3])
    call  _print_string                // print Again?
    int64 r0 = sp
    int   r1 = stackframe              // max. size of input buffer
    call  _gets_s                      // read answer as string
    int8  r1 = [sp] | 0x20             // read first character of answer, convert to lower case
}   while (int8+ r1 == 'y')            // repeat if user enters 'y'

// write goodbye text
int64 r0 = address([text4])
call  _print_string                    // print goodbye

int64 sp += stackframe                 // release stack frame

int r0 = 0
return                                 // return from main

_main end

code end