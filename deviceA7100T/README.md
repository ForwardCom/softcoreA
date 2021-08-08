# Device-specific files

Device specific files for implementing a ForwardCom softcore in Nexys A7 FPGA board with Xilinx Artix 7 100T FPGA.

See the [manual](https://github.com/ForwardCom/softcoreA/raw/main/softcore_A.pdf) for details.

##

Files included |  Description
--- | ---
Nexys-A7-100T.xdc  |  constraints file specifying input and output pins
bitstream_settings_a.xdc  |  constraints file
A1.xpr.zip  |  zipfile with entire Vivado project
A1.xpr  |   Vivado project file
A1T100R32.bit  |  compiled bitstream for 32-bit register version of softcore
A1T100R64.bit  |  compiled bitstream for 64-bit register version of softcore
config_r32.vh  |  configuration file for 32-bit register version
config_r64.vh  |  configuration file for 64-bit register version
debugger.vh  |  source code for debugger on 7-segment display
debug_display.sv  |  source code for debugger on external LCD display
hello.ex  |  executable file with Hello World example
calculator.ex  |  executable file with calculator example
guess_number.ex  |  executable file with guessing game example
tests_arithmetics.ex  |  executable file with tests of arithmetic instructions
tests_bool_bit.ex  |  executable file with tests of boolean and bit manipulation instructions
tests_branch.ex  |  executable file with tests of jump and branch instructions
tests_formats.ex   |  executable file with tests of instruction formats
