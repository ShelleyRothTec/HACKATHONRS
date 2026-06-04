module accelerometer_top (
    input           MAX10_CLK1_50,
    input   [9:0]   SW,
    input   [1:0]   KEY,
    output  [9:0]   LEDR,
    output  [7:0]   HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout   [15:0]  ARDUINO_IO,
    inout           ARDUINO_RESET_N
);

    // Clock and reset
    logic clk, rst_n;
    assign clk = MAX10_CLK1_50;
    assign rst_n = KEY[0];
    
    // ADXL345 is connected to JP1 GPIO header:
    // GPIO[2] = SPI_MOSI
    // GPIO[3] = SPI_MISO
    // GPIO[4] = SPI_CLK
    // GPIO[5] = SPI_CS_N
    // (Alternatively could use I2C on pins GPIO[0], GPIO[1])
    
    // For now using UART on JP1:
    // Assign UART TX to be sent to ESP32
    // Assign JP1 header pins for SPI
    logic spi_mosi, spi_miso, spi_clk, spi_cs_n;
    logic uart_tx;
    
    // Make unused ARDUINO_IO high-Z
    assign ARDUINO_IO = 16'hZZZZ;
    assign ARDUINO_RESET_N = 1'bZ;
    
    // Acceleration data
    logic [15:0] accel_x, accel_y, accel_z;
    logic adxl_data_valid;
    logic adxl_busy;
    
    // State machine to periodically read and transmit acceleration
    typedef enum logic [1:0] {
        IDLE_STATE,
        READING,
        TRANSMITTING,
        WAITING
    } main_state_t;
    
    main_state_t main_state, main_next_state;
    logic [31:0] read_interval_count;
    logic start_adxl_read;
    logic uart_busy;
    logic start_uart;
    logic adxl_read_done;
    
    // Counter for read interval (~100 ms at 50 MHz)
    localparam READ_INTERVAL = 32'd5_000_000;  // 100 ms
    
    // State machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            main_state <= IDLE_STATE;
        else
            main_state <= main_next_state;
    end
    
    always_comb begin
        main_next_state = main_state;
        case (main_state)
            IDLE_STATE: begin
                if (read_interval_count >= READ_INTERVAL)
                    main_next_state = READING;
            end
            READING: begin
                if (adxl_read_done)
                    main_next_state = TRANSMITTING;
            end
            TRANSMITTING: begin
                if (!uart_busy)
                    main_next_state = WAITING;
            end
            WAITING: begin
                main_next_state = IDLE_STATE;
            end
        endcase
    end
    
    // Counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_interval_count <= 32'h0;
        end else begin
            case (main_state)
                IDLE_STATE: begin
                    read_interval_count <= read_interval_count + 1;
                end
                default: begin
                    read_interval_count <= 32'h0;
                end
            endcase
        end
    end
    
    // Control signals
    assign start_adxl_read = (main_state == IDLE_STATE && read_interval_count >= READ_INTERVAL);
    assign start_uart = (main_state == TRANSMITTING && !uart_busy);
    
    // Detect ADXL read completion
    logic adxl_data_valid_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            adxl_data_valid_prev <= 1'b0;
        else
            adxl_data_valid_prev <= adxl_data_valid;
    end
    assign adxl_read_done = adxl_data_valid && !adxl_data_valid_prev;
    
    // Instantiate ADXL345 SPI controller
    adxl345_spi adxl_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_adxl_read),
        .busy(adxl_busy),
        .data_valid(adxl_data_valid),
        .accel_x(accel_x),
        .accel_y(accel_y),
        .accel_z(accel_z),
        .spi_clk(spi_clk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n)
    );
    
    // Instantiate UART TX
    uart_tx uart_transmit (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_uart),
        .busy(uart_busy),
        .tx(uart_tx),
        .byte0(accel_x[7:0]),
        .byte1(accel_x[15:8]),
        .byte2(accel_y[7:0]),
        .byte3(accel_y[15:8]),
        .byte4(accel_z[7:0]),
        .byte5(accel_z[15:8])
    );
    
    // Display acceleration values on 7-segment displays (for debug)
    // Convert acceleration to hex for display
    logic [3:0] disp0, disp1, disp2, disp3;
    assign disp0 = accel_x[3:0];
    assign disp1 = accel_x[7:4];
    assign disp2 = accel_y[3:0];
    assign disp3 = accel_y[7:4];
    
    // 7-segment decoder
    seg7_decoder seg0 (.hex(disp0), .seg(HEX0));
    seg7_decoder seg1 (.hex(disp1), .seg(HEX1));
    seg7_decoder seg2 (.hex(disp2), .seg(HEX2));
    seg7_decoder seg3 (.hex(disp3), .seg(HEX3));
    seg7_decoder seg4 (.hex(4'h0), .seg(HEX4));
    seg7_decoder seg5 (.hex(4'h0), .seg(HEX5));
    
    // LED indicators for tilt direction
    logic [9:0] tilt_leds;
    always_comb begin
        tilt_leds = 10'h000;
        if (accel_x > 16'h0200)  tilt_leds[7:5] = 3'b111;  // Right
        if (accel_x < 16'hFE00)  tilt_leds[4:2] = 3'b111;  // Left
        if (accel_y > 16'h0200)  tilt_leds[9:8] = 2'b11;   // Forward
        if (accel_y < 16'hFE00)  tilt_leds[1:0] = 2'b11;   // Back
    end
    assign LEDR = tilt_leds;
    
    // JP1 GPIO header assignments (SPI to ADXL345 on GPIO pins)
    // This is a placeholder; actual pin assignments would be in .qsf file
    // GPIO[2:0] not used
    // GPIO[5:2] used for SPI: MOSI, MISO, CLK, CS_N
    
endmodule


// 7-segment decoder
module seg7_decoder (
    input   [3:0]   hex,
    output  [7:0]   seg
);

    always_comb begin
        case (hex)
            4'h0: seg = 8'b11000000;
            4'h1: seg = 8'b11111001;
            4'h2: seg = 8'b10100100;
            4'h3: seg = 8'b10110000;
            4'h4: seg = 8'b10011001;
            4'h5: seg = 8'b10010010;
            4'h6: seg = 8'b10000010;
            4'h7: seg = 8'b11111000;
            4'h8: seg = 8'b10000000;
            4'h9: seg = 8'b10010000;
            4'hA: seg = 8'b10001000;
            4'hB: seg = 8'b10000011;
            4'hC: seg = 8'b11000110;
            4'hD: seg = 8'b10100001;
            4'hE: seg = 8'b10000110;
            4'hF: seg = 8'b10001110;
        endcase
    end

endmodule
