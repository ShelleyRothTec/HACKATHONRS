// ============================================================
// Volt-Meter Challenge - FPGA side
//
// Receives UART lines from ESP32:
//   V000\n
//   V165\n
//   V330\n
//
// Displays voltage as X.XX on HEX2 HEX1 HEX0.
// LEDR[9:0] shows voltage level proportionally.
//
// UART wiring:
//   ESP32 GPIO16 TX -> FPGA ARDUINO_IO[0]
//   FPGA ARDUINO_IO[1] -> ESP32 GPIO17 RX, not used here
//   ESP32 GND <-> FPGA GND
// ============================================================

module voltmeter_top (
    input  wire        MAX10_CLK1_50,
    input  wire [9:0]  SW,
    input  wire [1:0]  KEY,

    output wire [9:0]  LEDR,

    output wire [7:0]  HEX0,
    output wire [7:0]  HEX1,
    output wire [7:0]  HEX2,
    output wire [7:0]  HEX3,
    output wire [7:0]  HEX4,
    output wire [7:0]  HEX5,

    inout  wire [15:0] ARDUINO_IO,
    output wire        ARDUINO_RESET_N
);

    wire clk   = MAX10_CLK1_50;
    wire rst_n = KEY[0];

    // Keep Arduino reset released.
    assign ARDUINO_RESET_N = 1'b1;

    // UART RX input from ESP32 TX.
    wire uart_rx_in;
    assign uart_rx_in = ARDUINO_IO[0];

    // ARDUINO_IO[0] is input only.
    // ARDUINO_IO[1] is unused TX-back-to-ESP32, kept idle high.
    assign ARDUINO_IO[0]    = 1'bz;
    assign ARDUINO_IO[1]    = 1'b1;
    assign ARDUINO_IO[15:2] = 14'bz;

    // 50 MHz / 9600 baud = 5208.333 clocks per UART bit.
    // 5208 is accurate enough for this challenge.
    localparam integer CLKS_PER_BIT = 5208;

    // ------------------------------------------------------------
    // Synchronize asynchronous UART input to FPGA clock
    // ------------------------------------------------------------

    reg rx_s1;
    reg rx_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s1 <= 1'b1;
            rx_s2 <= 1'b1;
        end else begin
            rx_s1 <= uart_rx_in;
            rx_s2 <= rx_s1;
        end
    end

    wire rx_bit = rx_s2;

    // ------------------------------------------------------------
    // UART RX engine, 9600 baud, 8N1
    // ------------------------------------------------------------

    localparam [1:0] RX_IDLE  = 2'd0;
    localparam [1:0] RX_START = 2'd1;
    localparam [1:0] RX_DATA  = 2'd2;
    localparam [1:0] RX_STOP  = 2'd3;

    reg [1:0]  rx_state;
    reg [12:0] rx_clk_cnt;
    reg [2:0]  rx_bit_idx;
    reg [7:0]  rx_shift;
    reg [7:0]  rx_byte;
    reg        rx_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state   <= RX_IDLE;
            rx_clk_cnt <= 13'd0;
            rx_bit_idx <= 3'd0;
            rx_shift   <= 8'd0;
            rx_byte    <= 8'd0;
            rx_done    <= 1'b0;
        end else begin
            rx_done <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    if (rx_bit == 1'b0) begin
                        rx_clk_cnt <= 13'd0;
                        rx_state   <= RX_START;
                    end
                end

                RX_START: begin
                    if (rx_clk_cnt == ((CLKS_PER_BIT - 1) / 2)) begin
                        if (rx_bit == 1'b0) begin
                            rx_clk_cnt <= 13'd0;
                            rx_bit_idx <= 3'd0;
                            rx_state   <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 13'd1;
                    end
                end

                RX_DATA: begin
                    if (rx_clk_cnt == (CLKS_PER_BIT - 1)) begin
                        rx_clk_cnt <= 13'd0;
                        rx_shift[rx_bit_idx] <= rx_bit;

                        if (rx_bit_idx == 3'd7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_idx <= rx_bit_idx + 3'd1;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 13'd1;
                    end
                end

                RX_STOP: begin
                    if (rx_clk_cnt == (CLKS_PER_BIT - 1)) begin
                        rx_byte <= rx_shift;
                        rx_done <= 1'b1;
                        rx_state <= RX_IDLE;
                        rx_clk_cnt <= 13'd0;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 13'd1;
                    end
                end

                default: begin
                    rx_state <= RX_IDLE;
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Parse packet format: V123
    //
    // V123 means 1.23V.
    // V330 means 3.30V.
    // ------------------------------------------------------------

    localparam [1:0] PARSE_WAIT_V = 2'd0;
    localparam [1:0] PARSE_D0     = 2'd1;
    localparam [1:0] PARSE_D1     = 2'd2;
    localparam [1:0] PARSE_D2     = 2'd3;

    reg [1:0] parse_state;

    reg [3:0] digit_before_decimal;
    reg [3:0] digit_tenths;
    reg [3:0] digit_hundredths;

    reg [3:0] buf_d0;
    reg [3:0] buf_d1;

    reg [9:0] voltage_cv; // centivolts, 0..330

    wire rx_is_digit = (rx_byte >= 8'h30) && (rx_byte <= 8'h39);
    wire [3:0] rx_digit = rx_byte[3:0];
    wire [9:0] candidate_cv = (buf_d0 * 10'd100) + (buf_d1 * 10'd10) + rx_digit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parse_state <= PARSE_WAIT_V;

            digit_before_decimal <= 4'd0;
            digit_tenths         <= 4'd0;
            digit_hundredths     <= 4'd0;

            buf_d0 <= 4'd0;
            buf_d1 <= 4'd0;

            voltage_cv <= 10'd0;
        end else begin
            if (rx_done) begin
                case (parse_state)
                    PARSE_WAIT_V: begin
                        if ((rx_byte == 8'h56) || (rx_byte == 8'h76)) begin // 'V' or 'v'
                            parse_state <= PARSE_D0;
                        end
                    end

                    PARSE_D0: begin
                        if (rx_is_digit) begin
                            buf_d0 <= rx_digit;
                            parse_state <= PARSE_D1;
                        end else begin
                            parse_state <= PARSE_WAIT_V;
                        end
                    end

                    PARSE_D1: begin
                        if (rx_is_digit) begin
                            buf_d1 <= rx_digit;
                            parse_state <= PARSE_D2;
                        end else begin
                            parse_state <= PARSE_WAIT_V;
                        end
                    end

                    PARSE_D2: begin
                        if (rx_is_digit) begin
                            // Accept the new full value only after all 3 digits arrive.
                            digit_before_decimal <= buf_d0;
                            digit_tenths         <= buf_d1;
                            digit_hundredths     <= rx_digit;

                            if (candidate_cv > 10'd330) begin
                                voltage_cv <= 10'd330;
                            end else begin
                                voltage_cv <= candidate_cv;
                            end
                        end

                        parse_state <= PARSE_WAIT_V;
                    end

                    default: begin
                        parse_state <= PARSE_WAIT_V;
                    end
                endcase
            end
        end
    end

    // ------------------------------------------------------------
    // 7-segment decoder
    //
    // DE10-Lite HEX displays are active-low:
    //   0 = segment on
    //   1 = segment off
    //
    // HEX[7] is decimal point, also active-low.
    // ------------------------------------------------------------

    function [7:0] seg7;
        input [3:0] d;
        begin
            case (d)
                4'd0: seg7 = 8'b1100_0000;
                4'd1: seg7 = 8'b1111_1001;
                4'd2: seg7 = 8'b1010_0100;
                4'd3: seg7 = 8'b1011_0000;
                4'd4: seg7 = 8'b1001_1001;
                4'd5: seg7 = 8'b1001_0010;
                4'd6: seg7 = 8'b1000_0010;
                4'd7: seg7 = 8'b1111_1000;
                4'd8: seg7 = 8'b1000_0000;
                4'd9: seg7 = 8'b1001_0000;
                default: seg7 = 8'b1111_1111;
            endcase
        end
    endfunction

    // Display X.XX using HEX2 HEX1 HEX0.
    // Put decimal point after HEX2.
    assign HEX2 = seg7(digit_before_decimal) & 8'b0111_1111;
    assign HEX1 = seg7(digit_tenths);
    assign HEX0 = seg7(digit_hundredths);

    // Turn off unused displays.
    assign HEX3 = 8'hFF;
    assign HEX4 = 8'hFF;
    assign HEX5 = 8'hFF;

    // LED bar graph.
    // 3.30V / 10 LEDs = 0.33V per LED.
    assign LEDR[0] = (voltage_cv >= 10'd33);
    assign LEDR[1] = (voltage_cv >= 10'd66);
    assign LEDR[2] = (voltage_cv >= 10'd99);
    assign LEDR[3] = (voltage_cv >= 10'd132);
    assign LEDR[4] = (voltage_cv >= 10'd165);
    assign LEDR[5] = (voltage_cv >= 10'd198);
    assign LEDR[6] = (voltage_cv >= 10'd231);
    assign LEDR[7] = (voltage_cv >= 10'd264);
    assign LEDR[8] = (voltage_cv >= 10'd297);
    assign LEDR[9] = (voltage_cv >= 10'd330);

endmodule
