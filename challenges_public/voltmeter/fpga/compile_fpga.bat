@echo off
REM Compile the Volt-Meter FPGA project.
REM Run this file from inside the fpga folder.

"C:\intelFPGA_lite\17.1\quartus\bin64\quartus_sh.exe" --flow compile voltmeter_top
pause
