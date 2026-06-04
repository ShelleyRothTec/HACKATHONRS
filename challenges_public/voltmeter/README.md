# Volt-Meter Challenge Project

This folder contains a complete starter environment for Challenge 1: Volt-Meter.

It has:

```text
voltmeter/
├── esp32/
│   ├── platformio.ini
│   └── src/
│       └── main.cpp
└── fpga/
    ├── voltmeter_top.qpf
    ├── voltmeter_top.qsf
    ├── compile_fpga.bat
    ├── program_fpga.bat
    └── src/
        └── voltmeter_top.sv
```

## 1. Where to put this folder

Copy the `voltmeter` folder into:

```text
TechCrash2026/challenges_public/
```

So the final path should be:

```text
TechCrash2026/challenges_public/voltmeter/
```

## 2. Wiring

### Potentiometer to ESP32

```text
Pot one outer pin  -> ESP32 3V3
Pot middle pin     -> ESP32 GPIO34
Pot other outer pin -> ESP32 GND
```

The two outer pins can be swapped. The middle pin must stay on GPIO34.

### OLED to ESP32

```text
OLED VCC -> ESP32 3V3
OLED GND -> ESP32 GND
OLED SDA -> ESP32 GPIO21
OLED SCL -> ESP32 GPIO22
```

### ESP32 to FPGA UART

```text
ESP32 GPIO16 -> FPGA ARDUINO_IO[0]
FPGA ARDUINO_IO[1] -> ESP32 GPIO17
ESP32 GND <-> FPGA GND
```

For this voltmeter, the most important UART wire is GPIO16 -> ARDUINO_IO[0].

## 3. ESP32 upload

Open a terminal inside:

```text
TechCrash2026/challenges_public/voltmeter/esp32
```

Run:

```powershell
pio run
pio run -t upload
pio device monitor
```

The serial monitor should show lines like:

```text
ADC=2048  Voltage=1.65V  Sent=V165
```

## 4. FPGA compile and program

Open a terminal inside:

```text
TechCrash2026/challenges_public/voltmeter/fpga
```

Compile:

```powershell
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_sh.exe" --flow compile voltmeter_top
```

Program:

```powershell
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_pgm.exe" -c "USB-Blaster [USB-0]" -m JTAG -o "P;output_files\voltmeter_top.sof"
```

If your USB-Blaster name is different, first run:

```powershell
& "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_pgm.exe" --list
```

## 5. Expected result

When you turn the potentiometer:

- OLED shows `0.00V` to `3.30V`
- FPGA seven-segment displays show `0.00` to `3.30`
- LEDR[9:0] fills proportionally

Example:

```text
OLED: 1.65V
FPGA HEX: 1.65
LEDR: about 5 LEDs on
```
