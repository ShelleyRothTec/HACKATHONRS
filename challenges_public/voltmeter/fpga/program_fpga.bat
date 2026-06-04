@echo off
REM Program the Volt-Meter FPGA project.
REM Run this after compile_fpga.bat finishes successfully.

"C:\intelFPGA_lite\17.1\quartus\bin64\quartus_pgm.exe" --list
"C:\intelFPGA_lite\17.1\quartus\bin64\quartus_pgm.exe" -c "USB-Blaster [USB-0]" -m JTAG -o "P;output_files\voltmeter_top.sof"
pause
