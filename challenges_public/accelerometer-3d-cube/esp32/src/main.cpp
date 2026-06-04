#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <math.h>

// OLED Display
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// UART configuration for FPGA communication
#define RX_PIN 16  // ESP32 RX from FPGA TX
#define TX_PIN 17  // ESP32 TX to FPGA RX
#define UART_SPEED 9600
#define UART_NUM UART_NUM_2

// 3D Cube vertices (normalized coordinates)
struct Point3D {
    float x, y, z;
};

struct Point2D {
    float x, y;
};

// Cube vertices (8 corners of a cube)
const Point3D cube_vertices[8] = {
    {-1, -1, -1}, {1, -1, -1}, {1, 1, -1}, {-1, 1, -1},  // Back face
    {-1, -1, 1},  {1, -1, 1},  {1, 1, 1},  {-1, 1, 1}   // Front face
};

// Cube edges (indices into vertices)
const uint8_t cube_edges[12][2] = {
    {0, 1}, {1, 2}, {2, 3}, {3, 0},  // Back face
    {4, 5}, {5, 6}, {6, 7}, {7, 4},  // Front face
    {0, 4}, {1, 5}, {2, 6}, {3, 7}   // Connecting edges
};

// Acceleration data from FPGA
int16_t accel_x = 0, accel_y = 0, accel_z = 0;
bool new_accel_data = false;

// 3D rotation and projection
Point3D rotated_vertices[8];
Point2D projected_vertices[8];

// Function prototypes
void init_display();
void uart_init();
void read_uart_data();
void rotate_cube(float pitch, float roll);
void project_3d_to_2d();
void draw_cube();
void draw_text_info();
float map_accel_to_angle(int16_t accel_val);

void setup() {
    Serial.begin(115200);
    delay(100);
    
    // Initialize I2C and OLED display
    Wire.begin();
    init_display();
    
    // Initialize UART2 for FPGA communication
    uart_init();
    
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(WHITE);
    display.setCursor(0, 0);
    display.println("Accel Cube");
    display.println("Waiting for FPGA...");
    display.display();
    
    delay(1000);
}

void loop() {
    // Read incoming UART data from FPGA
    read_uart_data();
    
    if (new_accel_data) {
        new_accel_data = false;
        
        // Convert raw acceleration to pitch and roll angles
        // Scale: assume ADXL345 outputs in ±16g range, map to ±90 degrees
        float pitch = map_accel_to_angle(accel_y);  // Y controls pitch (forward/back)
        float roll = map_accel_to_angle(accel_x);   // X controls roll (left/right)
        
        // Rotate cube based on acceleration
        rotate_cube(pitch, roll);
        
        // Project 3D points to 2D
        project_3d_to_2d();
        
        // Clear and redraw display
        display.clearDisplay();
        
        // Draw 3D cube
        draw_cube();
        
        // Draw acceleration values
        draw_text_info();
        
        display.display();
    }
    
    delay(20);  // ~50 Hz update rate
}

void init_display() {
    if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
        Serial.println(F("SSD1306 allocation failed"));
        for (;;);  // Halt
    }
    
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(WHITE);
    display.display();
}

void uart_init() {
    // Configure UART2 with custom RX/TX pins
    // Default UART2 uses GPIO16 (RX) and GPIO17 (TX)
    Serial2.begin(UART_SPEED, SERIAL_8N1, RX_PIN, TX_PIN);
}

void read_uart_data() {
    if (Serial2.available() >= 6) {
        // Read 6 bytes: X_low, X_high, Y_low, Y_high, Z_low, Z_high
        uint8_t data[6];
        for (int i = 0; i < 6; i++) {
            data[i] = Serial2.read();
        }
        
        // Assemble 16-bit signed values (little-endian from FPGA)
        accel_x = (int16_t)((data[1] << 8) | data[0]);
        accel_y = (int16_t)((data[3] << 8) | data[2]);
        accel_z = (int16_t)((data[5] << 8) | data[4]);
        
        new_accel_data = true;
        
        // Debug output
        // Serial.printf("Accel: X=%d, Y=%d, Z=%d\n", accel_x, accel_y, accel_z);
    }
}

float map_accel_to_angle(int16_t accel_val) {
    // Map acceleration range [-32768, 32767] to angle range [-90, 90] degrees
    // ADXL345 outputs in units of ~4 mg/LSB in ±16g mode
    // Assume ~8000 represents approximately ±1g
    float angle = (float)accel_val / 32768.0 * 90.0;
    
    // Clamp to [-90, 90]
    if (angle > 90.0) angle = 90.0;
    if (angle < -90.0) angle = -90.0;
    
    return angle;
}

void rotate_cube(float pitch_deg, float roll_deg) {
    // Convert degrees to radians
    float pitch = pitch_deg * M_PI / 180.0;
    float roll = roll_deg * M_PI / 180.0;
    
    // Precompute sin/cos
    float sin_pitch = sin(pitch);
    float cos_pitch = cos(pitch);
    float sin_roll = sin(roll);
    float cos_roll = cos(roll);
    
    // Apply rotation to each vertex
    for (int i = 0; i < 8; i++) {
        Point3D v = cube_vertices[i];
        Point3D r;
        
        // Pitch rotation (around X-axis)
        r.x = v.x;
        r.y = v.y * cos_pitch - v.z * sin_pitch;
        r.z = v.y * sin_pitch + v.z * cos_pitch;
        
        // Roll rotation (around Z-axis)
        float x_temp = r.x * cos_roll - r.y * sin_roll;
        float y_temp = r.x * sin_roll + r.y * cos_roll;
        r.z = r.z;
        
        rotated_vertices[i].x = x_temp;
        rotated_vertices[i].y = y_temp;
        rotated_vertices[i].z = r.z;
    }
}

void project_3d_to_2d() {
    // Perspective projection to 2D screen coordinates
    // Screen center at (64, 32), scale factor for size
    
    for (int i = 0; i < 8; i++) {
        float z = rotated_vertices[i].z + 4.0;  // Add offset to avoid negative z
        float scale = 40.0 / z;  // Perspective scaling
        
        // Project to 2D (with screen offset)
        projected_vertices[i].x = 64 + rotated_vertices[i].x * scale;
        projected_vertices[i].y = 32 - rotated_vertices[i].y * scale;  // Y inverted for display
    }
}

void draw_cube() {
    // Draw edges connecting vertices
    for (int i = 0; i < 12; i++) {
        int v0 = cube_edges[i][0];
        int v1 = cube_edges[i][1];
        
        int x0 = (int)projected_vertices[v0].x;
        int y0 = (int)projected_vertices[v0].y;
        int x1 = (int)projected_vertices[v1].x;
        int y1 = (int)projected_vertices[v1].y;
        
        // Clamp to screen bounds
        if (x0 >= 0 && x0 < SCREEN_WIDTH && y0 >= 0 && y0 < SCREEN_HEIGHT &&
            x1 >= 0 && x1 < SCREEN_WIDTH && y1 >= 0 && y1 < SCREEN_HEIGHT) {
            display.drawLine(x0, y0, x1, y1, WHITE);
        }
    }
    
    // Draw vertices as small dots
    for (int i = 0; i < 8; i++) {
        int x = (int)projected_vertices[i].x;
        int y = (int)projected_vertices[i].y;
        
        if (x >= 0 && x < SCREEN_WIDTH && y >= 0 && y < SCREEN_HEIGHT) {
            display.drawPixel(x, y, WHITE);
            display.drawPixel(x + 1, y, WHITE);
            display.drawPixel(x, y + 1, WHITE);
            display.drawPixel(x + 1, y + 1, WHITE);
        }
    }
}

void draw_text_info() {
    // Display acceleration data and angles
    display.setTextSize(1);
    display.setTextColor(WHITE);
    display.setCursor(0, 0);
    
    float pitch = map_accel_to_angle(accel_y);
    float roll = map_accel_to_angle(accel_x);
    
    display.printf("P:%.0f R:%.0f", pitch, roll);
    
    display.setCursor(0, 56);
    display.printf("X:%d Y:%d Z:%d", accel_x, accel_y, accel_z);
}
