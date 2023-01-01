/**************************  tests_branch.as  *******************************
* Author:        Agner Fog
* date created:  2021-07-07
* last modified: 2021-07-20
* Version:       1.11
* Project:       ForwardCom Test suite, assembly code
* Description:   Test jump, call, and branch instructions with general 
*                purpose registers
*
* This test program will test jump, call, and branch instructions and 
* output a list of which instructions are working for int8, int16, int32, 
* and int64 operands.
*
* Copyright 2021 GNU General Public License v.3 http://www.gnu.org/licenses
******************************************************************************/

// Library functions in libc_light.li
extern _puts:     function reguse=3,0            // write string + linefeed to stdout
extern _printf:   function reguse=0xF,0          // write formatted string to stdout

const section read ip                            // read-only data section
// Text strings:

text1: int8 "\nForwardCom test suite\nTest jump, call, and branch instructions"  // intro text,
       int8 "\nPress Run to continue"
       int8 "\n                          int8   int16  int32  int64", 0          // and heading
newline: int8 "\n", 0                                                            // newline
press_run: int8 "\nPress Run to continue", 0

format1: int8 "\n%-26s%3c%7c%7c%7c", 0           // format string for printing results

// text strings for each instruction:
text_sub_jz:              int8 "sub/jump_zero", 0
text_sub_jneg:            int8 "sub/jump_neg", 0
text_sub_jpos:            int8 "sub/jump_pos", 0
text_sub_joverfl:         int8 "sub/jump_overfl", 0
text_sub_jborrow:         int8 "sub/jump_borrow", 0

text_add_jz:              int8 "add/jump_zero", 0
text_add_jneg:            int8 "add/jump_neg", 0
text_add_jpos:            int8 "add/jump_pos", 0
text_add_joverfl:         int8 "add/jump_overfl", 0
text_add_jcarry:          int8 "add/jump_carry", 0

text_and_jz:              int8 "and/jump_zero", 0
text_or_jz:               int8 "or /jump_zero", 0
text_xor_jz:              int8 "xor/jump_zero", 0

text_test_bit_jtrue:      int8 "test_bit/jump_true", 0
text_test_bits_and_jtrue: int8 "test_bits_and/jump_true", 0
text_test_bits_or_jtrue:  int8 "test_bits_or/jump_true", 0

text_compare_jequal:      int8 "compare/jump_equal", 0
text_compare_jsbelow:     int8 "compare/jump_sbelow", 0
text_compare_jsabove:     int8 "compare/jump_sabove", 0
text_compare_jubelow:     int8 "compare/jump_ubelow", 0
text_compare_juabove:     int8 "compare/jump_uabove", 0

text_inc_compare_jbelow:  int8 "increment_compare/j_below", 0
text_inc_compare_jabove:  int8 "increment_compare/j_above", 0
text_sub_maxlen_jpos:     int8 "sub_maxlen/jump_pos", 0

text_jump_relative:       int8 "jump_relative pointer", 0
text_call_relative:       int8 "call_relative pointer", 0
text_jump_relative_table: int8 "jump_relative table", 0
text_call_relative_table: int8 "call_relative table", 0

text_jump_absolute:       int8 "jump absolute pointer", 0
text_call_absolute:       int8 "call absolute pointer", 0
text_jump_register:       int8 "jump to register", 0
text_call_register:       int8 "call to register", 0
text_jump_32:             int8 "jump 32 bit offset", 0
text_call_32:             int8 "call 32 bit offset", 0

// not supported:
//text_jump_64:           int8 "jump 64 bit absolute", 0
//text_call_64:           int8 "call 64 bit absolute", 0

// relative jump tables
jumptab8:  int8  (TARGET1-TARGET3)/4, (TARGET2-TARGET3)/4, 0, (TARGET4-TARGET3)/4, (TARGET5-TARGET3)/4, 0
jumptab16: int16 (TARGET1-TARGET3)/4, (TARGET2-TARGET3)/4, 0, (TARGET4-TARGET3)/4, (TARGET5-TARGET3)/4, 0
jumptab32: int32 (TARGET1-TARGET3)/4, (TARGET2-TARGET3)/4, 0, (TARGET4-TARGET3)/4, (TARGET5-TARGET3)/4, 0
jumptab64: int64 (TARGET1-TARGET3)/4, (TARGET2-TARGET3)/4, 0, (TARGET4-TARGET3)/4, (TARGET5-TARGET3)/4, 0

const end


code1 section execute                            // code section

__entry_point function public                    // skip startup code
_main function public

/* register use:
r0:  bits indicating success for int8, int16, int32, int64
r1:  operand
r2:  operand
r3:  result
r4:  scratch
r6:  int64 supported
r20: return address when testing jump
*/

// print intro text and heading
int64  r0 = address [text1]                      // address of string
//call   _puts                                   // print string and linefeed
call   _printf                                   // print string without linefeed

breakpoint                                       // debug breakpoint

int    r1 = 1
int    capab2 = write_capabilities(r1, 0)        // disable error trap for unknown instructions

// Test of each instruction:

// Test sub/jump_zero
int    r1 = 1
int    r0 = 1
int8   r2 = sub(r1,1), jump_zero A1
int    r0 = 0
A1:
int16  r3 = sub(r2,1), jump_zero A2
int32  r4 = r3 == 0xFFFF
int    r0 |= 2, mask = r4
       jump   A3
A2:    int r0 = 0
A3: 
int32  r3 = sub(r3,0xFFFF), jump_zero A4
       jump  A5
A4:    int r0 |= 4
A5:
int64  r4 = sub(r0,7), jump_nzero A8
int64  r1 = r0 | 1 << 60
int64  r4 = sub(r1,7), jump_zero A8
int    r0 |= 8
A8:
int64  r1 = address [text_sub_jz]
call   print_result


// Test sub/jump_neg
int    r1 = 0x100
int8   r3 = sub(r1,1), jump_neg A10
int    r0 = 0
       jump A11
A10:   int r0 = 1
A11:
int16  r3 = sub(r3,r3), jump_neg A12
int    r0 |= 2
       jump A13
A12:   int r0 = 0
A13:
int32  r2 = -8      // sub(r3,-8) would be converted to add(r3,8)
int32  r3 = sub(r3, r2), jump_nneg A14
       jump A15
A14:   int r4 = r3 == 8
       int r0 |= 4, mask = r4
A15:
int64  r2 = 9
int64  r4 = sub(r3,r2), jump_nneg A16
int64  r5 = r4 == -1
int64  r3 |= 1 << 62
int64  r4 = sub(r3,r2), jump_neg A16
int    r0 |= 8, mask = r5
A16:
int64  r1 = address [text_sub_jneg]
call   print_result


// Test sub/jump_pos
int    r1 = 1
int    r2 = 0x100
int8   r3 = sub(r2,r1), jump_pos A30
int    r0 = r3 == 0xFF
       jump A31
A30:   int r0 = 0
A31:
int16  r3 = sub(r1,r3), jump_pos A32
int    r4 = r3 == 0xFF02
int    r0 |= 2, mask = r4
jump   A33
A32:   int r0 = 0
A33:
int32  r3 = sub(r2,r2), jump_npos A34
int    r0 = 0
jump   A35
A34:   int r4 = r3 == 0
       int r0 |= 4, mask = r4
A35:
int64  r1 |= 1 << 62
int64  r3 = sub(r1,r2), jump_npos A36
int    r0 |= 8
A36:
int64  r1 = address [text_sub_jpos]
call   print_result


// Test sub/jump_overflow
int    r1 = 0xA0
int    r2 = 0x21
int8   r3 = sub(r1,r2), jump_overfl A40
int    r0 = 0
jump   A41
A40:   int r0 = 1
A41:
int    r1 = 0xA000
int    r2 = 0x2000
int16  r3 = sub(r1,r2), jump_overfl A42
int    r0 |= 2
jump   A43
A42:   int r0 = 0
A43:
int32  r1 = 0x50000000
int32  r2 = 0xD0000000
int32  r3 = sub(r1,r2), jump_overfl A44
int    r0 = 0
jump   A45
A44:   int r0 |= 4
A45:
int64  r3 = sub(r1,r2), jump_noverfl A46
jump   A47
A46:   int64 r4 = r3 == 0xFFFFFFFF80000000
       int r0 |= 8, mask = r4
A47:
int64  r1 = address [text_sub_joverfl]
call   print_result


// Test sub/jump_borrow
int    r1 = 0x1280
int    r2 = 0x1281
int8   r3 = sub(r1,r2), jump_borrow A50
int    r0 = 0
jump   A51
A50:   int r0 = 1
A51:
int16  r3 = sub(r1,r2), jump_nborrow A52
int32  r4 = r3 == 0x0000FFFF
int    r0 |= 2, mask = r4
A52:
int32  r3 = sub(r1,r2), jump_nborrow A54
int64  r4 = r3 == 0x0000FFFFFFFF
int    r0 |= 4, mask = r4
A54:
int64  r1 |= 1 << 60
int64  r3 = sub(r2,r1), jump_nborrow A56
int    r0 |= 8
A56:
int64  r1 = address [text_sub_jborrow]
call   print_result


// Test add/jump_zero
int    r1 = 0x1271
int    r2 = 0x128F
int8   r3 = add(r1,r2), jump_zero B0
int    r0 = 0
jump   B1
B0:    int r0 = 1
B1:
int16  r3 = add(r1,r2), jump_zero B2
int    r0 |= 2
B2:
int32  r2 = -0x1271
int32  r3 = add(r1,r2), jump_nzero B4
int    r0 |= 4
B4:
int64  r3 = add(r1,r2), jump_zero B6
int    r0 |= 8
B6:
int64  r1 = address [text_add_jz]
call   print_result


// Test add/jump_neg
int    r1 = 0x1261
int    r2 = 0x1220
int8   r3 = add(r1,r2), jump_neg B10
int    r0 = 0
jump   B11
B10:   int r0 = 1
B11:
int16  r3 = add(r1,r2), jump_neg B12
int    r0 |= 2
B12:
int32  r2 = -0x1262
int32  r3 = add(r1,r2), jump_nneg B14
int    r0 |= 4
B14:
int64  r3 = add(r1,r2), jump_neg B16
int    r0 |= 8
B16:
int64  r1 = address [text_add_jneg]
call   print_result


// Test add/jump_pos
int    r1 = 0x1261
int    r2 = 0x1220
int8   r3 = add(r1,r2), jump_npos B20
int    r0 = 0
jump   B21
B20:   int r0 = r3 == 0x81
B21:
int32  r2 = -r1
int16  r3 = add(r1,r2), jump_pos B22
int32  r4 = r3 == 0
int    r0 |= 2, mask = r4
B22:
int32  r3 = add(r2,0), jump_pos B24
int    r0 |= 4
B24:
int64  r3 = add(r1,r2), jump_npos B26
int64  r4 = r3 == 1 << 32
int    r0 |= 8, mask = r4
B26:
int64  r1 = address [text_add_jpos]
call   print_result


// Test add/jump_overfl
int32  r1 = 0x1261
int32  r2 = 0x1220
int8   r3 = add(r1,r2), jump_overfl B30
int    r0 = 0
jump   B31
B30:   int r0 = 1
B31:
int16  r3 = add(r1,r2), jump_overfl B32
int    r0 |= 2
B32:
int32  r2 = 0x7FFFF000
int32  r3 = add(r1,r2), jump_noverfl B34
int    r0 |= 4
B34:
int64  r3 = add(r1,r2), jump_overfl B36
int    r0 |= 8
B36:
int64  r1 = address [text_add_joverfl]
call   print_result


// Test add/jump_carry
int32  r1 = 0x1261
int32  r2 = 0x1220
int8   r3 = add(r1,r2), jump_ncarry B40
int    r0 = 0
jump   B41
B40:   int r0 = 1
B41:
int16  r3 = add(r1,r2), jump_carry B42
int    r0 |= 2
B42:
int32  r2 = -r1
int32  r3 = add(r1,r2), jump_ncarry B44
int    r0 |= 4
B44:
int64  r2 <<= 32
int64  r3 = add(r2,r2), jump_ncarry B46
int    r0 |= 8
B46:
int64  r1 = address [text_add_jcarry]
call   print_result


// Test and/jump_zero
int32  r1 = 0x0100F055
int32  r2 = 0x10AA
int8   r3 = and(r1,r2), jump_zero C0
int    r0 = 0
jump   C1
C0:    int r0 = 1
C1:
int16  r3 = and(r1,r2), jump_zero C2
int    r4 = r3 == 0x1000
int    r0 |= 2, mask = r4
C2:
int32  r2 = 0x02220FAA
int32  r3 = and(r1,r2), jump_nzero C4
int    r0 |= 4
C4:
int64  r1 |= 1 << 60
int64  r2 |= 1 << 60
int64  r3 = and(r1,r2), jump_zero C6
int64  r4 = r3 == 1 << 60
int    r0 |= 8, mask = r4
C6:
int64  r1 = address [text_and_jz]
call   print_result


// Test or/jump_zero
int32  r1 = 0xF055
int32  r2 = 0x0FAA
int8   r3 = or(r1,r2), jump_zero C10
int    r0 = r3 == 0xFF
jump   C11
C10:   int r0 = 0
C11:
int    r1 = 0
int    r2 = 0
int16  r3 = or(r1,r2), jump_nzero C12
int    r0 |= 2
C12:
int32  r1 = 1 << 31
int32  r3 = or(r1,r2), jump_zero C14
int32  r4 = r3 == 1 << 31
int    r0 |= 4, mask = r4
C14:
int64  r1 = 1 << 32
int64  r3 = or(r1,r2), jump_zero C16
int64  r4 = r3 == 1 << 32
int    r0 |= 8, mask = r4
C16:
int64  r1 = address [text_or_jz]
call   print_result


// Test xor/jump_zero
int32  r1 = 0xF055
int32  r2 = r1
int8   r3 = xor(r1,r2), jump_zero C20
int    r0 = 0
jump   C21
C20:   int r0 = 1
C21:
int    r2 = 0
int16  r3 = xor(r1,r2), jump_zero C22
int32  r4 = r3 == r1
int    r0 |= 2, mask = r4
C22:
int32  r1 = -r1
int32  r2 = r1
int32  r3 = xor(r1,r2), jump_nzero C24
int    r0 |= 4
C24:
int64  r1 |= 1 << 63
int64  r3 = xor(r1,r2), jump_zero C26
int    r0 |= 8
C26:
int64  r1 = address [text_xor_jz]
call   print_result


// Test test_bit/jump_true
int32  r1 = 0x12345678
int8   test_bit(r1,4), jump_true E0
int    r0 = 0
jump   E1
E0:    int r0 = 1
E1:
int16  test_bit(r1,8), jump_true E2
int    r0 |= 2
E2:
int32  test_bit(r1,21), jump_false E4
int    r0 |= 4
E4:
int64  test_bit(r1,33), jump_true E6
int64  r1 |= 1 << 33
int64  test_bit(r1,33), jump_false E6
int    r0 |= 8
E6:
int64  r1 = address [text_test_bit_jtrue]
call   print_result


// Test test_bits_and/jump_true
int32  r1 = 0x12345678
int32  r2 = 0x2670
int8   test_bits_and(r1,r2), jump_true E10
int    r0 = 0
jump   E11
E10:   int r0 = 1
E11:
int16  test_bits_and(r1,r2), jump_true E12
int    r0 |= 2
E12:
int32  test_bits_and(r1,r1), jump_false E14
int    r0 |= 4
E14:
int64  r2 = r1 | 1 << 50
int64  test_bits_and(r1,r2), jump_true E16
int    r0 |= 8
E16:
int64  r1 = address [text_test_bits_and_jtrue]
call   print_result


// Test test_bits_or/jump_true
int32  r1 = 0x12345678
int32  r2 = 0xC0
int8   test_bits_or(r1,r2), jump_false E20
int    r0 = 1
jump   E21
E20:   int r0 = 0
E21:
int16  test_bits_or(r1,0x1001), jump_false E22
int    r0 |= 2
E22:
int32  test_bits_or(r2,0x1001), jump_true E24
int    r0 |= 4
E24:
int32  r2 = r1 ^ -1
int64  test_bits_or(r2,r1), jump_false E26
int    r0 &= ~ 4
E26:
int64  r1 |= 1 << 60
int64  r2 |= 1 << 60
int64  test_bits_or(r2,r1), jump_false E28
int    r0 |= 8
E28:
int64  r1 = address [text_test_bits_or_jtrue]
call   print_result


int64  r0 = address [press_run]                  // press run to continue
call   _printf                                   // print string

breakpoint


// Test compare/jump_equal
int32  r1 = 0x222212AB
int32  r2 = 0x222213AB
int8   compare(r1,r2), jump_equal F0
int    r0 = 0
jump   F1
F0:    int r0 = 1
F1:
int16  compare(r1,r2), jump_equal F2
int    r0 |= 2
F2:
int32  r2 &= ~0x100
int32  compare(r1,r2), jump_nequal F4
int    r0 |= 4
F4:
int64  r1 ^= 1 << 60
int64  compare(r1,r2), jump_equal F6
int    r0 |= 8
F6:
int64  r1 = address [text_compare_jequal]
call   print_result


// Test compare/jump_sbelow
int    r1 = 0x1111997F
int    r2 = 0x22228880
int8   compare(r1,r2), jump_sbelow F10
int    r0 = 1
jump   F11
F10:   int r0 = 0
F11:
int16  compare(r1,r2), jump_sbelow F12
int    r0 |= 2
F12:
int32  compare(r1,r2), jump_saboveeq F14
int    r0 |= 4
F14:
int64  r2 |= 1 << 63
int64  compare(r1,r2), jump_sbelow F16
int    r0 |= 8
F16:
int64  r1 = address [text_compare_jsbelow]
call   print_result


// Test compare/jump_sabove
int    r1 = 0x1111997F
int    r2 = 0x22228880
int8   compare(r1,r2), jump_sbeloweq F20
int    r0 = 1
jump   F21
F20:   int r0 = 0
F21:
int16  compare(r1,r2), jump_sbeloweq F22
int    r0 |= 2
F22:
int32  compare(r1,r2), jump_sabove F24
int    r0 |= 4
F24:
int32  compare(r1,r1), jump_sbeloweq F25
int    r0 &= ~ 4
F25:
int64  r2 |= 1 << 63
int64  compare(r1,r2), jump_sbeloweq F26
int    r0 |= 8
F26:
int64  r1 = address [text_compare_jsabove]
call   print_result


// Test compare/jump_ubelow
int    r1 = 0x1111997F
int    r2 = 0x22228880
int8   compare(r1,r2), jump_ubelow F30
int    r0 = 0
jump   F31
F30:   int r0 = 1
F31:
int16  compare(r1,r2), jump_ubelow F32
int    r0 |= 2
F32:
int32  compare(r1,r2), jump_uaboveeq F34
int    r0 |= 4
F34:
int32  compare(r1,r1), jump_uaboveeq F35
int    r0 &= ~ 4
F35:
int64  compare(r1,r2), jump_uaboveeq F36
int64  r1 |= 1 << 63
int64  compare(r1,r2), jump_ubelow F36
int    r0 |= 8
F36:
int64  r1 = address [text_compare_jubelow]
call   print_result


// Test compare/jump_uabove
int    r1 = 0x1111997F
int    r2 = 0x22228880
int8   compare(r1,r2), jump_ubeloweq F40
int    r0 = 0
jump   F41
F40:   int r0 = 1
F41:
int16  compare(r1,r2), jump_ubeloweq F42
int    r0 |= 2
F42:
int32  compare(r1,r2), jump_uabove F44
int    r0 |= 4
F44:
int32  compare(r1,r1), jump_ubeloweq F45
int    r0 &= ~ 4
F45:
int64  compare(r1,r2), jump_uabove F46
int64  r1 |= 1 << 63
int64  compare(r1,r2), jump_ubeloweq F46
int    r0 |= 8
F46:
int64  r1 = address [text_compare_juabove]
call   print_result


// Test inc_compare/jump_below
int    r2 = 0
for (int8 r1 = 0; r1 < 5; r1++) {
    int r2++
}
int    r0 = r2 == 5
for (int16 r1 = 0x7000; r1 < 0x7005; r1++) {
    int r2++
}
int    r4 = r2 == 10
int    r0 |= 2, mask = r4

for (int32 r1 = -2; r1 < 3; r1++) {
    int r2++
}
int32  r4 = r2 == 15
int    r0 |= 4, mask = r4
int32  r1 = 0x7FFFFFFE
int64  r3 = r1 + 5
for (int64 ; r1 < r3; r1++) {
    int r2++
}
int32  r4 = r2 == 20
int    r0 |= 8, mask = r4
int64  r1 = address [text_inc_compare_jbelow]
call   print_result


// Test inc_compare/jump_above
int    r2 = 0
for (int8 r1 = 0; r1 <= 5; r1++) {
    int r2++
}
int    r0 = r2 == 6
int    r3 = 0x7005
for (int16 r1 = 0x7000; r1 <= r3; r1++) {
    int r2++
}
int    r4 = r2 == 12
int    r0 |= 2, mask = r4

for (int32 r1 = -2; r1 <= 3; r1++) {
    int r2++
}
int32  r4 = r2 == 18
int    r0 |= 4, mask = r4
int32  r1 = 0x7FFFFFFE
int64  r3 = r1 + 5
for (int64 ; r1 <= r3; r1++) {
    int r2++
}
int32  r4 = r2 == 24
int    r0 |= 8, mask = r4
int64  r1 = address [text_inc_compare_jabove]
call   print_result


// Test sub_maxlen/jump_pos
// get max vector length without using vectors:
int    r6 = 0
int64  r6 = sub_maxlen(r6, 3), jump_pos H1
int    r6 = - r6                                 // max vector length
int    r2 = 0
H1:    int r0 = 0
if (int r6 > 0) {                                // avoid infinite loops if maxlen = 0
  // test all operand sizes for completeness, even though only int64 is used. int8 is likely to overflow
  int   r1 = 4 
  H10:  int r2++
  int8  r1 = sub_maxlen(r1, 3), jump_pos H10
  int   r0 = r2 == 1

  int   r1 = r6 << 2
  int   r2 = 0
  H20:  int r2++
  int16 r1 = sub_maxlen(r1, 3), jump_pos H20
  int   r4 = r2 == 4
  int   r0 |= 2, mask = r4

  int   r1 = r6 << 2
  int   r1 += 4
  int   r2 = 0
  H30:  int r2++
  int32 r1 = sub_maxlen(r1, 3), jump_pos H30
  int   r4 = r2 == 5
  int   r0 |= 4, mask = r4

  int64 r3 = 1 << 60
  int64 r1 = sub_maxlen(r1, 3), jump_npos H42  
  int   r1 = r6 << 2
  int   r1 += 4
  int   r2 = 0
  H40:  int r2++
  int64 r1 = sub_maxlen(r1, 3), jump_pos H40
  int   r4 = r2 == 5
  int   r0 |= 8, mask = r4
  H42:
}
int64  r1 = address [text_sub_maxlen_jpos]
call   print_result


// Test jump to relative pointer in memory
int    r1 = 0
int64  r10 = address [TARGET3]
int64  r11 = address [jumptab8]
int64  r20 = address [K00]
int8   jump_relative(r10,[r11])
K00:   int r0 = r3 == 1

int64  r20 = address [K10]
int16  jump_relative(r10,[jumptab16+4])
K10:   int r4 = r3 == 3
int    r0 |= 2, mask = r4

int64  r20 = address [K20]
int32  jump_relative(r10,[jumptab32+4])
K20:   int r4 = r3 == 2
int    r0 |= 4, mask = r4

int64  r20 = address [K30]
int64  r11 = address [jumptab64]
int64  jump_relative(r10,[r11+24])
K30:   int r4 = r3 == 4
int    r0 |= 8, mask = r4

int64  r1 = address [text_jump_relative]
call   print_result


// Test call to relative pointer in memory
int    r1 = 0
int64  r20 = address [TARGETRETURN]
int64  r11 = address [jumptab8]
int8   call_relative(r10,[r11])
int r0 = r3 == 1

int16  call_relative(r10,[jumptab16+4])
int    r4 = r3 == 3
int    r0 |= 2, mask = r4

int32  call_relative(r10,[jumptab32+4])
int    r4 = r3 == 2
int    r0 |= 4, mask = r4

int64  r11 = address [jumptab64]
int64  call_relative(r10,[r11+24])
int r4 = r3 == 4
int    r0 |= 8, mask = r4

int64  r1 = address [text_call_relative]
call   print_result


// Test jump to relative table in memory
int    r1 = 0
int64  r10 = address [TARGET3]
int64  r11 = address [jumptab8]
int64  r20 = address [L00]
int8   jump_relative(r10,[r11+r1])
L00:   int r4 = r3
int    r1 = 1
int64  r20 = address [L01]
int8   jump_relative(r10,[r11+r1])
L01:   int r4 <<= 4
       int r4 |= r3
int    r1 = 4
int64  r20 = address [L02]
int8   jump_relative(r10,[r11+r1])
L02:   int r4 <<= 4
int    r4 |= r3
int    r0 = r4 == 0x125

int    r1 = 2
int64  r11 = address [jumptab16]
int64  r20 = address [L10]
int16  jump_relative(r10,[r11+r1*2])
L10:   int r4 = r3
int    r1 = 1
int64  r20 = address [L11]
int16  jump_relative(r10,[r11+r1*2])
L11:   int r4 <<= 4
       int r4 |= r3
int    r1 = 3
int64  r20 = address [L12]
int16  jump_relative(r10,[r11+r1*2])
L12:   int r4 <<= 4
int    r4 |= r3
int    r4 = r4 == 0x324
int    r0 |= 2, mask = r4

int    r1 = 4
int64  r11 = address [jumptab32]
int64  r20 = address [L20]
int32  jump_relative(r10,[r11+r1*4])
L20:   int r4 = r3
int    r1 = 2
int64  r20 = address [L21]
int32  jump_relative(r10,[r11+r1*4])
L21:   int r4 <<= 4
       int r4 |= r3
int    r1 = 3
int64  r20 = address [L22]
int32  jump_relative(r10,[r11+r1*4])
L22:   int r4 <<= 4
int    r4 |= r3
int    r4 = r4 == 0x534
int    r0 |= 4, mask = r4

int    r1 = 0
int64  r11 = address [jumptab64]
int64  r20 = address [L30]
int64  jump_relative(r10,[r11+r1*8])
L30:   int r4 = r3
int    r1 = 4
int64  r20 = address [L31]
int64  jump_relative(r10,[r11+r1*8])
L31:   int r4 <<= 4
       int r4 |= r3
int    r1 = 2
int64  r20 = address [L32]
int64  jump_relative(r10,[r11+r1*8])
L32:   int r4 <<= 4
int    r4 |= r3
int    r4 = r4 == 0x153
int    r0 |= 8, mask = r4

int64  r1 = address [text_jump_relative_table]
call   print_result


// Test call to relative table in memory
int    r1 = 2
int64  r10 = address [TARGET3]
int64  r11 = address [jumptab8]
int64  r20 = address [TARGETRETURN]
int8   call_relative(r10,[r11+r1])
int    r4 = r3
int    r1 = 4
int8   call_relative(r10,[r11+r1])
int    r4 <<= 4
int    r4 |= r3
int    r1 = 3
int8   call_relative(r10,[r11+r1])
int    r4 <<= 4
int    r4 |= r3
int    r0 = r4 == 0x354

int64  r11 = address [jumptab16]
int    r1 = 2
int16  call_relative(r10,[r11+r1*2])
int    r4 = r3
int    r1 = 0
int16  call_relative(r10,[r11+r1*2])
int    r4 <<= 4
int    r4 |= r3
int    r1 = 4
int16  call_relative(r10,[r11+r1*2])
int    r4 <<= 4
int    r4 |= r3
int    r4 = r4 == 0x315
int    r0 |= 2, mask = r4

int64  r11 = address [jumptab32]
int    r1 = 4
int32  call_relative(r10,[r11+r1*4])
int    r4 = r3
int    r1 = 1
int32  call_relative(r10,[r11+r1*4])
int    r4 <<= 4
int    r4 |= r3
int    r1 = 2
int32  call_relative(r10,[r11+r1*4])
int    r4 <<= 4
int    r4 |= r3
int    r4 = r4 == 0x523
int    r0 |= 4, mask = r4

int64  r11 = address [jumptab64]
int    r1 = 3
int64  call_relative(r10,[r11+r1*8])
int    r4 = r3
int    r1 = 4
int64  call_relative(r10,[r11+r1*8])
int    r4 <<= 4
int    r4 |= r3
int    r1 = 0
int64  call_relative(r10,[r11+r1*8])
int    r4 <<= 4
int    r4 |= r3
int    r4 = r4 == 0x451
int    r0 |= 8, mask = r4

int64  r1 = address [text_call_relative_table]
call   print_result


// jump/call 24 bit relative need not be tested because we would not have got here if they didn't work
// jump/call to register value need not be tested because we would not have got here if they didn't work
int    r0 = 0x78
int64  r1 = address [text_jump_register]
call   print_result
int    r0 = 0x78
int64  r1 = address [text_call_register]
call   print_result


int64  sp -= 32                                  // allocate space on stack

// test jump absolute address in memory
int64  r2 = address [TARGET2]
int64  r3 = address [TARGET3]
int64  [sp] = r2                                 // put jump target address on stack
int64  [sp+8] = r3                               // put jump target address on stack
int64  r20 = address [M10]                       // destination for jump back
int64  jump ([sp+8])                             // 8 bit offset, format 1.6.1B
nop
M10:   int r4 = r3 == 3
int64  r1 = sp + 0x1000
int64  r20 = address [M11]                       // destination for jump back
int64  jump ([r1-0x1000])                        // 32 bit offset, format 2.5.2B
nop
M11:   int r4 = r3 == 2 && r4
int    r0 = r4 ? 0x78 : 0

int64  r1 = address [text_jump_absolute]
call   print_result


// test call absolute address in memory
int64  r20 = address [TARGETRETURN]
int    r3 = 0
int64  call ([sp])                               // 8 bit offset, format 1.6.1B
int    r4 = r3 == 2
int    r0 = r4 ? 0x78 : 0
int64  r1 = address [text_call_absolute]
call   print_result


// test jump 32 bit relative
options codesize = 1 << 30                       // make sure to use 32-bit jump address
int64  r20 = address [M20]
int    r3 = 0
jump   TARGET4
nop
M20:
int    r4 = r3 == 4
int    r0 = r4 ? 0x78 : 0
int64  r1 = address [text_jump_32]
call   print_result


// test call 32 bit relative
int64  r20 = address [TARGETRETURN]
int    r3 = 0
call   TARGET3
nop
int    r4 = r3 == 3
int    r0 = r4 ? 0x78 : 0
int64  r1 = address [text_call_32]
call   print_result
options codesize = 0                             // return to default codesize

int64  sp += 32                                  // free allocated space on stack


int64 r0 = address [newline]
call   _printf                                   // print string


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

/*
(If you add more test outputs here, you need another breakpoint because 
 the output buffer is close to full and the screen on RealTerm will be 
 full as well.)
*/

code1 end


code2 section execute
// jump targets in a separate section for possible longer jump distance

TARGET1: int r3 = 1
jump  r20                    // jump back

TARGET2: int r3 = 2
jump  r20                    // jump back

TARGET3: int r3 = 3
jump  r20                    // jump back

TARGET4: int r3 = 4
jump  r20                    // jump back

TARGET5: int r3 = 5
jump  r20                    // jump back

TARGETRETURN: nop            // for call/return
return

code2 end
