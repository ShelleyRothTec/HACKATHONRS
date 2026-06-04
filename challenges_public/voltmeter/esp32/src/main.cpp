#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ============================================================
// Volt-Meter Challenge - ESP32 side
//
// Hardware:
//   Pot middle pin  -> ESP32 GPIO34
//   Pot outer pin   -> ESP32 3V3
//   Pot outer pin   -> ESP32 GND
//
//   OLED SDA        -> ESP32 GPIO21
//   OLED SCL        -> ESP32 GPIO22
//   OLED VCC        -> ESP32 3V3
//   OLED GND        -> ESP32 GND
//
//   ESP32 GPIO16 TX -> FPGA ARDUINO_IO[0]
//   ESP32 GPIO17 RX <- FPGA ARDUINO_IO[1]
//   ESP32 GND       <-> FPGA GND
// ============================================================

// Pin definitions used by the TechCrash2026 kit
static const int PIN_ANALOG_IN = 34;
static const int PIN_OLED_SDA  = 21;
static const int PIN_OLED_SCL  = 22;
static const int PIN_FPGA_TX   = 16; // ESP32 TX -> FPGA RX
static const int PIN_FPGA_RX   = 17; // ESP32 RX <- FPGA TX

static const int OLED_WIDTH    = 128;
static const int OLED_HEIGHT   = 64;
static const int OLED_I2C_ADDR = 0x3C;
static const int FPGA_BAUD     = 9600;

Adafruit_SSD1306 oled(OLED_WIDTH, OLED_HEIGHT, &Wire, -1);
HardwareSerial FpgaSerial(2);

int readAveragedAdc()
{
    long sum = 0;
    for (int i = 0; i < 16; i++) {
        sum += analogRead(PIN_ANALOG_IN);
        delayMicroseconds(200);
    }
    return (int)(sum / 16);
}

void drawOled(float voltage, int adcRaw, int percent)
{
    oled.clearDisplay();
    oled.setTextColor(SSD1306_WHITE);

    oled.setTextSize(1);
    oled.setCursor(0, 0);
    oled.print("Digital Volt-Meter");

    char voltageText[10];
    snprintf(voltageText, sizeof(voltageText), "%.2fV", voltage);

    oled.setTextSize(3);
    oled.setCursor(4, 20);
    oled.print(voltageText);

    oled.setTextSize(1);
    oled.setCursor(0, 54);
    oled.print("ADC=");
    oled.print(adcRaw);
    oled.print("  ");
    oled.print(percent);
    oled.print("%");

    oled.display();
}

void setup()
{
    Serial.begin(115200);
    delay(500);

    Serial.println();
    Serial.println("Starting Volt-Meter Challenge");

    analogReadResolution(12); // ESP32 ADC range: 0..4095
    analogSetPinAttenuation(PIN_ANALOG_IN, ADC_11db); // good for approx 0..3.3V

    Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
    bool oledOk = oled.begin(SSD1306_SWITCHCAPVCC, OLED_I2C_ADDR);

    if (!oledOk) {
        Serial.println("OLED failed. Check VCC/GND/SDA/SCL wiring.");
    } else {
        oled.clearDisplay();
        oled.setTextColor(SSD1306_WHITE);
        oled.setTextSize(1);
        oled.setCursor(0, 0);
        oled.println("Volt-Meter Ready");
        oled.display();
    }

    // UART2: begin(baud, config, RX pin, TX pin)
    FpgaSerial.begin(FPGA_BAUD, SERIAL_8N1, PIN_FPGA_RX, PIN_FPGA_TX);
    Serial.println("UART to FPGA started: 9600 baud, 8N1.");
}

void loop()
{
    static unsigned long lastUpdate = 0;
    unsigned long now = millis();

    // Update 10 times per second
    if (now - lastUpdate < 100) {
        return;
    }
    lastUpdate = now;

    int adcRaw = readAveragedAdc();

    // Convert ADC value to voltage.
    // 0    -> 0.00V
    // 4095 -> 3.30V
    float voltage = adcRaw * 3.3f / 4095.0f;

    int centivolts = (int)(voltage * 100.0f + 0.5f); // 1.65V -> 165
    if (centivolts < 0) centivolts = 0;
    if (centivolts > 330) centivolts = 330;

    int percent = map(adcRaw, 0, 4095, 0, 100);
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;

    // Send a simple packet to FPGA:
    // V000\n, V165\n, V330\n, etc.
    FpgaSerial.printf("V%03d\n", centivolts);

    Serial.printf("ADC=%4d  Voltage=%.2fV  Sent=V%03d\n",
                  adcRaw, voltage, centivolts);

    drawOled(voltage, adcRaw, percent);
}
