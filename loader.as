/****************************  loader.as  ********************************
* Author:        Agner Fog
* date created:  2020-12-04
* Last modified: 2021-07-30
* Version:       1.11
* Project:       Loader for ForwardCom soft core
* Language:      ForwardCom assembly
* Description:
* This loader is designed to run in a ForwardCom processor to load an 
* executable file into code and data RAM before running the loaded program.
*
* Copyright 2020-2021 GNU General Public License v.3 http://www.gnu.org/licenses
******************************************************************************

Prerequisites:
The executable file to be loaded is structured as defined in the ForwardCom 
ELF specification defined in the file elf_forwardcom.h.
The sections are sorted into blocks in the following order 
(see CLinker::sortSections() in file linker.cpp):
* const (ip)
* code (ip)
* data (datap)
* bss (datap)
* data (threadp)
* bss (threadp)
The binary data sections are stored in the executable file in the same order
as the program headers.
The executable file is position-independent. No relocation of addresses in
the code is needed.
The program has only one thread.
The available RAM is sufficient.
The input is loaded as bytes through a serial input port (BAUD rate set in defines.vh)

The data will be stored in the processor memory in the following order:

1. data (at beginning of data memory. Addressed by datap)
2. bss (uninitialized data, immediately after data. Addressed by datap)
3. free space to use for heap and stack. (The stack pointer will point to the end of this space)
4. threadp data (immediately before const. Addressed by threadp)
5. const data (at end of data memory. Addressed by IP)
6. code (at beginning of code memory. Addressed by IP)
7. loader code (at end of code memory)


Instructions for how to modify and rebuild the loader:
-----------------------------------------------------------

1. The first instruction must be a direct jump to the loader code that
loads an executable program (*.ex file). The load button will go to this 
address.

The second instruction at address 1 (word-based) must be an entry for the 
restart code that will restart a previously loaded program. The reset button 
will go to this address. The restart code must set datap, threadp, sp, and 
the entry point to the values previously calculated by the loader. 
The present version stores these values in instructions in the code section 
in order to free the entire data memory for the running program. 
Note that we have execute and write access (int32 only) to the code memory, 
but not read access.

2. Assemble:
forw -ass -debug -binlist loader.as -list=loader.txt 

3. Link:
forw -link -hex2 loader.mem loader.ob 

4. Replace the file loader.mem in the softcore project with the new version.

5. Check size:
The size of the code section of the loader can be found from the address of 
the last instruction in the file loader.txt produced by step 2.
If this size (in 32-bit words) exceeds the value MAX_LOADER_SIZE
defined in the file defines.vh, then the value of MAX_LOADER_SIZE must
be increased to at least the actual size. The value must be even.

The loader code will be placed at an address calculated as the end of the 
code memory minus MAX_LOADER_SIZE. 

6. Rebuild the soft core project.

*****************************************************************************/

// Definition of serial input ports
%serial_input_port   = 8                              // serial input port, read one byte at a time
%serial_input_status = 9                              // serial input status. bit 0-15 = number of bytes in input buffer


// Definition of offsets in the file header (struct ElfFwcEhdr in elf_forwardcom.h):
%e_ident        = 0x00  //  uint8_t   e_ident[16];    // Magic number and other info
%e_type         = 0x10  //  uint16_t  e_type;         // Object file type
%e_machine      = 0x12  //  uint16_t  e_machine;      // Architecture
%e_version      = 0x14  //  uint32_t  e_version;      // Object file version
%e_entry        = 0x18  //  uint64_t  e_entry;        // Entry point virtual address
%e_phoff        = 0x20  //  uint64_t  e_phoff;        // Program header table file offset
%e_shoff        = 0x28  //  uint64_t  e_shoff;        // Section header table file offset
%e_flags        = 0x30  //  uint32_t  e_flags;        // Processor-specific flags. We may define any values for these flags
%e_ehsize       = 0x34  //  uint16_t  e_ehsize;       // ELF header size in bytes
%e_phentsize    = 0x36  //  uint16_t  e_phentsize;    // Program header table entry size
%e_phnum        = 0x38  //  uint16_t  e_phnum;        // Program header table entry count
%e_shentsize    = 0x3A  //  uint16_t  e_shentsize;    // Section header table entry size
%e_shnum        = 0x3C  //  uint32_t  e_shnum;        // Section header table entry count (was uint16_t)
%e_shstrndx     = 0x40  //  uint32_t  e_shstrndx;     // Section header string table index (was uint16_t)
%e_stackvect    = 0x44  //  uint32_t  e_stackvect;    // number of vectors to store on stack. multiply by max vector length and add to stacksize
%e_stacksize    = 0x48  //  uint64_t  e_stacksize;    // size of stack for main thread
%e_ip_base      = 0x50  //  uint64_t  e_ip_base;      // __ip_base relative to first ip based segment
%e_datap_base   = 0x58  //  uint64_t  e_datap_base;   // __datap_base relative to first datap based segment
%e_threadp_base = 0x60  //  uint64_t  e_threadp_base; // __threadp_base relative to first threadp based segment
%file_header_size = 0x68                              // size of file header

%ELFMAG         = 0x464C457F // 0x7F 'E' 'L' 'F': identifying number at e_ident


// Definition of offsets in program headers (struct ElfFwcPhdr in elf_forwardcom.h):
%p_type         = 0x00  //  uint32_t  p_type;         // Segment type
%p_flags        = 0x04  //  uint32_t  p_flags;        // Segment flags
%p_offset       = 0x08  //  uint64_t  p_offset;       // Segment file offset
%p_vaddr        = 0x10  //  uint64_t  p_vaddr;        // Segment virtual address
%p_paddr        = 0x18  //  uint64_t  p_paddr;        // Segment physical address (not used. indicates first section instead)
%p_filesz       = 0x20  //  uint64_t  p_filesz;       // Segment size in file
%p_memsz        = 0x28  //  uint64_t  p_memsz;        // Segment size in memory
%p_align        = 0x30  //  uint8_t   p_align;        // Segment alignment
%p_unused       = 0x31  //  uint8_t   unused[7];

// Definition of section flags
%SHF_EXEC       = 0x0001     // Executable
%SHF_WRITE      = 0x0002     // Writable
%SHF_READ       = 0x0004     // Readable
%SHF_IP         = 0x1000     // Addressed relative to IP (executable and read-only sections)
%SHF_DATAP      = 0x2000     // Addressed relative to DATAP (writeable data sections)
%SHF_THREADP    = 0x4000     // Addressed relative to THREADP (thread-local data sections)

// Start of RAM address
%ram_start_address = 0

// stack alignment
%stack_align = 1 << 4        // alignment of stack


/* Register use in this loader
r0:  number of bytes to read from input
r1:  current address in ram
r6:  ram address of current program header
r10: ram_start_address  
r11: number of bytes read from input = current position in input file
r12: size of each program header
r13: size of all threadp sections
r14: current program header index
r20: ram address of first program header
r21: number of program headers
r22: temporary start address for program data (later moved to 0)
r23: start address of const data
r24: start address of code section
r25: start address of threadp sections
r26: end of initialized data section, start of BSS
r27: size of code memory
r28: end of data and bss sections
r29: start address of loader
r30: error code
*/


/*********************************************
        Program code for loader
*********************************************/

code section execute align = 8

__entry_point function public
_loader  function public

// Loader entry:
jump LOADER

// Restart entry. This will restart a previously loaded program:
RESTART:

// Dummy constants make sure the following instructions are 2-word size. 
// These constants will be changed by the loader
set_sp: 
int32 sp = 0xDEADBEEF                            // will be replaced by calculated stack address
set_datap:
int32 r1 = 0xC001F001                            // will be replaced by calculated 32-bit datap value
int64 datap = write_spec(r1)                     // save datap register
set_threadp:
int32 r2 = 0xFEE1600D                            // will be replaced by calculated 32-bit threadp value
int64 threadp = write_spec(r2)                   // save threadp register

// clear input buffer
do { // repeat until no more serial input coming
    int r2 = 1
    int output(r2, r2, serial_input_status)      // clear input buffer
    for (int r1 = 0; r1 < 1000000; r1++) {}      // delay loop
    int16 r2 = input(r2, serial_input_status)    // check if there is more input
}
while (int16 r2 != 0)

// clear registers
int r0 = 0
int r1 = 0
int r2 = 0
int r3 = 0
int r4 = 0
int r5 = 0
int r6 = 0
int r7 = 0
int r8 = 0
int r9 = 0
int r10 = 0
int r11 = 0
int r12 = 0
int r13 = 0
int r14 = 0
int r15 = 0
int r16 = 0
int r17 = 0
int r18 = 0
int r19 = 0
int r20 = 0
int r21 = 0
int r22 = 0
int r23 = 0
int r24 = 0
int r25 = 0
int r26 = 0
int r27 = 0
int r28 = 0
int r29 = 0
int r30 = read_perf(perf0, -1)                   // clear all performance counters
int r30 = 0

// breakpoint

// To do: clear r0 - r30 using POP instruction if supported

set_entry_point:
jump LOADER                                      // this will be replaced by 24-bit relative call to program entry

breakpoint                                       // debug breakpoint in case main program returns
for (int;;){}                                    // stop in infinite loop


/*********************************************
           Loader starts here
*********************************************/

LOADER:

read_restart:

do {                                             // wait until there are at least 4 bytes in input buffer
    int16 r3 = input(r0, serial_input_status)    // bit 15:0 of status = number of bytes in input buffer (r0 is dummy)
} while (int16+ r3 < 4)                          // repeat if not enough data

// Read serial input and search for file header beginning with 0x7F, 'E', 'L', 'F'
int8 r3 = input(r0, serial_input_port)           // read first byte (r0 is dummy) 
if (int8+ r3 != 0x7F) {jump read_restart}
int8 r3 = input(r0, serial_input_port)           // read second byte
if (int8+ r3 != 'E')  {jump read_restart}
int8 r3 = input(r0, serial_input_port)           // read third byte
if (int8+ r3 != 'L')  {jump read_restart}
int8 r3 = input(r0, serial_input_port)           // read fourth byte
if (int8+ r3 != 'F')  {jump read_restart}

// Store file header in memory at address 0
//int64 r1 = ram_start_address                   // Store file header in memory at address 0 
//int32 [r1] = ELFMAG                            // store first word (superfluous. will not be used)
int r1 = 4                                       // we have read 4 bytes

// read_block function input: 
// r0: number of bytes to read
// r1: pointer to memory block to write to
// return:
// r0: last byte read
// r1: end of memory block

int r0 = file_header_size - 4                    // read program header (we have already read 4 bytes)
int r11 = r0 + r1                                // count number of bytes read
call read_block
int64 r10 = ram_start_address                    // Store file header in memory at address 0 

// read program headers
int32 r0 = [r10 + e_phoff]                       // file offset to first program header
int32 r0 -= r11                                  // number of bytes read so far
int r11 += r0                                    // count number of bytes read
call read_dummy                                  // read any space between file header and first program header

// round up to align by 8
int r1 += 7
int r1 &= -8

int r20 = r1                                     // save address of first program header
int16 r21 = [r10 + e_phnum]                      // number of program headers
int16 r12 = [r10 + e_phentsize]                  // size of each program header
// int r0 = r21 * r12                            // size of all program headers
int r0 = 0
for (int+ r14 = 0; r14 < r21; r14++) {           // multiplication loop in case CPU does not support multiplication
    int16 r0 += r12
}
int r11 += r0                                    // count number of bytes read
call read_block                                  // read all program headers

int r22 = r1 + 7                                 // temporary program data start address
int r22 &= -8                                    // align by 8

// find first code section
int32 r6 = r20                                   // ram address of first program header
for (int+ r14 = 0; r14 < r21; r14++) {           // loop through code sections
    int r3 = [r6 + p_flags]                      // section flags
    if (int8+ r3 & SHF_EXEC) {break}             // search for SHF_EXEC flag
    int r6 += r12                                // next program header
}

int r24 = read_capabilities(capab5, 0)           // get data cache size = start of code section
int r27 = read_capabilities(capab4, 0)           // get code cache size = max size of code section
int64 r4 = [r6 + p_vaddr]                        // virtual address of first code section relative to first IP section
int64 r23 = r24 - r4                             // start address of const data (ip-addressed)

// load binary data

// 1. const sections
int r1 = r23                                     // start address of const data
int32 r6 = r20                                   // ram address of first program header
for (int+ r14 = 0; r14 < r21; r14++) {           // loop through program headers
    int r3 = [r6 + p_flags]                      // section flags
    int16+ test_bits_and(r3, SHF_IP | SHF_READ), jump_false LOOP3BREAK // skip if not readable IP
    if (int16+ r3 & SHF_EXEC) {break}            // stop if SHF_EXEC flag
    int32 r0 = [r6 + p_offset]                   // file offset of this section
    int32 r0 -= r11                              // space between last program header and first binary data block
    int r11 += r0                                // count number of bytes read
    call read_dummy                              // read any space
    int32 r0 = [r6 + p_filesz]                   // file size of this section
    int32 r0 += 3                                // round up to nearest multiple of 4
    int32 r0 &= -4
    int r11 += r0                                // count number of bytes read
    call read_block                              // read const data section
    int r6 += r12                                // next program header
}
LOOP3BREAK:

// 2. code sections
for (int ; r14 < r21; r14++) {                   // continue loop through program headers
    int r3 = [r6 + p_flags]                      // section flags
    if (int16+ !(r3 & SHF_EXEC)) {break}         // stop if not SHF_EXEC flag
    int32 r0 = [r6 + p_offset]                   // file offset of this section
    int32 r0 -= r11                              // any space between last binary data and this
    int r11 += r0                                // count number of bytes read
    call read_dummy                              // read any space
    uint64 r1 = r23 + [r6 + p_vaddr]             // address to place code
    int32 r0 = [r6 + p_filesz]                   // file size of this section
    int32 r0 += 3                                // round up to nearest multiple of 4
    int32 r0 &= -4
    int r11 += r0                                // count number of bytes read
    call read_block                              // read code section
    int r6 += r12                                // next program header
}

int r30 = 1                                      // error code
int r29 = address([_loader])
if (uint32 r1 > r29) {jump ERROR}                // out of code memory

// 3. datap sections
// align first data section
int r3 = [r6 + p_flags]                          // section flags
if (int+ r3 & SHF_DATAP) {                       // check if there is a data or bss section
    int8  r4 = [r6 + p_align]
    int   r5 = 1
    int64 r5 <<= r4                              // alignment
    int64 r5 -= 1
    int64 r22 += r5
    int64 r5 = ~r5
    int64 r22 &= r5                              // aligned start address of program data
}

// data section headers
for (int ; r14 < r21; r14++) {                   // continue loop through program headers
    int r3 = [r6 + p_flags]                      // section flags
    if (int16+ !(r3 & SHF_DATAP)) {break}        // stop if not SHF_DATAP flag
    int32 r0 = [r6 + p_offset]                   // file offset of this section
    int32 r0 -= r11                              // any space between last binary data and this
    int r11 += r0                                // count number of bytes read
    call read_dummy                              // read any space
    int r1 = r22 + [r6 + p_vaddr]                // address to place code
    int r27 = r1 + [r6 + p_memsz]                // end of initialized and unitialized data section
    int32 r0 = [r6 + p_filesz]                   // file size of this section
    int32 r0 += 3                                // round up to nearest multiple of 4
    int32 r0 &= -4
    int r11 += r0                                // count number of bytes read. will be zero for BSS section
    call read_block                              // read code section
    int r6 += r12                                // next program header
    int r26 = r1                                 // end of initialized data section
}

// 4. threadp sections
int r13 = 0                                      // size of all threadp sections
int64 r25 = r23                                  // default if no threadp section. used for stack pointer
// find last threadp section
int r7 = r6
for (int r2 = r14; r2 < r21; r2++) {             // continue loop through program headers
    int r3 = [r7 + p_flags]                      // section flags
    if (int16+ !(r3 & SHF_THREADP)) {break}      // stop if not SHF_THREADP flag
    int r7 += r12                                // next program header
}
int r7 -= r12                                    // last threadp header, if any
if (int r7 >= r6) {                              // check if there is any threadp header
    int r13 = [r7 + p_vaddr]                     // virtual address of last threadp section relative to first threadp section
    int r13 += [r7 + p_memsz]                    // add size of last threadp section to get total size of threadp sections
    // start of threadp section
    int64 r25 = r23 - r13
    // align start of threadp sections
    int8  r4 = [r7 + p_align]                    // alignment of first threadp section
    int   r5 = 1
    int64 r5 <<= r4                              // alignment
    int64 r5 = -r5
    int64 r25 = r25 & r5                         // aligned start address of first threadp section
}

int r30 = 2                                      // error code
if (uint32 r25 <= r27) {jump ERROR}              // out of RAM memory
// r22 contains the amount or RAM used for headers during loading. 
// This is included in the memory count above, but will be freed before the loaded program is run.
// This freed memory will be available for data stack or heap

// threadp section headers
for (int ; r14 < r21; r14++) {                   // continue loop through program headers
    int r3 = [r6 + p_flags]                      // section flags
    if (int16+ !(r3 & SHF_THREADP)) {break}      // stop if not SHF_THREADP flag
    uint64 r1 = r25 + [r6 + p_vaddr]             // address to place code
    int32 r0 = [r6 + p_offset]                   // file offset of this section
    int32 r0 -= r11                              // any space between last binary data and this
    int r11 += r0                                // count number of bytes read
    call read_dummy                              // read any space
    int32 r0 = [r6 + p_filesz]                   // file size of this section (0 if BSS)
    int32 r0 += 3                                // round up to nearest multiple of 4
    int32 r0 &= -4
    int r11 += r0                                // count number of bytes read. will be zero for BSS section
    call read_block                              // read code section
    int r6 += r12                                // next program header
}

int64 r10 = ram_start_address                    // Store file header temporarily in memory at address 0 

// calculate entry point for loaded program
// r23 = const start = start of IP-addressed block
int64 r1 = r23 + [r10 + e_entry]                 // entry point
int64 r2 = address([set_entry_point+4])          // reference point
int32 r3 = r1 - r2                               // relative address
int32 r4 = r3 << 6                               // remove upper 8 bits and scale by 4 
uint32 r5 = r4 >> 8                              // 
int32 r6 = r5 | 0x79000000                       // code for direct call instruction
int32 [set_entry_point] = r6                     // modify set_entry_point instruction to call calculated entry point

// get datap
int64 r7 = [r10 + e_datap_base] /* + r22 */      // temporary datap address is r7+r22, but moved down to r7
int32 [set_datap+4] = r7                         // modify instruction that sets datap

// get threadp
int64 r8 = r25 + [r10 + e_threadp_base]          // threadp register
int32 [set_threadp+4] = r8                       // modify instruction that sets threadp

// get sp
int64 sp = r25 & -stack_align                    // align stack at end of datap ram = begin of threadp
int32 [set_sp+4] = sp                            // modify instruction that sets stack pointer

// Move data down from r22 to 0
int r2 = ram_start_address
for (int+ r3 = r22; r3 < r26; r3 += 4) {
    int32 r4 = [r3]
    int32 [r2] = r4
    int32 r2 += 4
}

// Fill the rest with zeroes, including BSS and empty space or stack
int r0 = 0
for (int ; r2 < r25; r2 += 4) {
    int32 [r2] = r0
}

// Initialize datap, threadp, sp. Jump to the entry point of the loaded program
jump RESTART

_loader end


// Error if out of memory or if input file sections are not in desired order
ERROR:
breakpoint
int r0 = r30                                     // show error code in debugger
jump ERROR


// Function to read a block of data into memory.
// input: 
// r0: number of bytes to read. must be divisible by 4
// r1: pointer to memory block to write to. must be aligned by 4
// return:
// r0: last word read
// r1: end of memory block
read_block function 
    int r30 = 0x10                               // error code
    if (int32 r0 < 0) {jump ERROR}               // check if negative
    int64 r2 = r1 + r0                           // end of memory block
    for (uint64 ; r1 < r2; r1 += 4) {            // loop n/4 times
        do {                                     // wait until there are at least 4 bytes in input buffer
            int32 r3 = input(r0, serial_input_status) // bit 15:0 of status = number of bytes in input buffer
        } while (int16 r3 < 4)                   // repeat if data not enough data
        int8 r3 = input(r0, serial_input_port)   // read first byte
        int8 r4 = input(r0, serial_input_port)   // read second byte
        int32 r4 <<= 8;
        int32 r3 |= r4
        int8 r4 = input(r0, serial_input_port)   // read third byte
        int32 r4 <<= 16;
        int32 r3 |= r4
        int8 r4 = input(r0, serial_input_port)   // read fourth byte
        int32 r4 <<= 24;
        int32 r3 |= r4
        int32 [r1] = r3                          // store byte to memory
    }
    return
read_block end

// Function to read a block of data and discard it
// input: 
// r0: number of bytes to read
// return:
// r0: last byte read
read_dummy function 
    int r30 = 0x11                               // error code
    if (int32 r0 < 0) {jump ERROR}               // check if negative
    for (uint64 ; r0 > 0; r0--) {                // loop n times
        do {
            int16 r3 = input(r0, serial_input_port) // read one byte. r0 is dummy
        } while (int16+ !(r3 & 0x100))           // repeat if data not ready
    }
    //int8 r0 = r3                               // return last byte read
    return
read_dummy end

nop

code end
