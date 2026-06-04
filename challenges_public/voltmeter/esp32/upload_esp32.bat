@echo off
REM Build and upload the ESP32 side.
REM Run this file from inside the esp32 folder.

pio run
pio run -t upload
pio device monitor
pause
