module adxl345_spi (
    input           clk,
    input           rst_n,
    input           start,          // Start reading acceleration
    output          busy,           // High while SPI transaction in progress
    output          data_valid,     // High when X, Y, Z data is ready
    
    // Data outputs (signed 16-bit, but ADXL345 gives signed 16-bit via 6-bit resolution shifted)
    output  [15:0]  accel_x,
    output  [15:0]  accel_y,
    output  [15:0]  accel_z,
    
    // SPI interface (to ADXL345)
    output          spi_clk,
    output          spi_mosi,
    input           spi_miso,
    output          spi_cs_n
);

    // ADXL345 Register addresses
    localparam DATAX0_REG = 8'h32;      // X-axis data 0
    localparam STATUS_REG = 8'h30;      // Status register
    
    // States for SPI state machine
    typedef enum logic [3:0] {
        IDLE,
        START_READ_STATUS,
        READ_STATUS_BYTE,
        START_READ_DATA,
        READ_ACCEL_DATA,
        COLLECT_DATA,
        DONE
    } state_t;
    
    state_t state, next_state;
    
    // SPI variables
    logic [7:0] spi_data_out, spi_data_in;
    logic [4:0] spi_bit_count;
    logic [7:0] read_address;
    logic spi_clk_en;
    logic spi_active;
    logic [7:0] byte_count;
    
    // Data buffers for each axis (6 bytes from ADXL345)
    logic [15:0] x_data, y_data, z_data;
    logic [7:0] accel_bytes [5:0];  // 6 bytes: XL, XH, YL, YH, ZL, ZH
    logic [2:0] byte_idx;
    
    // Clock divider for SPI clock (~1 MHz from 50 MHz)
    logic [5:0] clk_div;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_div <= 0;
        else
            clk_div <= clk_div + 1;
    end
    
    // Generate SPI clock (divide by ~25 to get ~1 MHz from 50 MHz)
    assign spi_clk = (spi_clk_en && clk_div[4]) ? ~clk_div[5] : 1'b0;
    
    // State machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start)
                    next_state = START_READ_DATA;
            end
            START_READ_DATA: begin
                next_state = READ_ACCEL_DATA;
            end
            READ_ACCEL_DATA: begin
                if (spi_bit_count == 0 && clk_div == 0 && byte_count == 8'd6)
                    next_state = COLLECT_DATA;
                else if (spi_bit_count == 0 && clk_div == 0)
                    next_state = READ_ACCEL_DATA;
            end
            COLLECT_DATA: begin
                next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
    
    // Output assignments
    assign busy = (state != IDLE && state != DONE);
    assign data_valid = (state == DONE);
    assign spi_cs_n = ~spi_active;
    assign spi_mosi = spi_data_out[7];
    
    // Assemble 16-bit acceleration values from bytes
    assign accel_x = {accel_bytes[1], accel_bytes[0]};
    assign accel_y = {accel_bytes[3], accel_bytes[2]};
    assign accel_z = {accel_bytes[5], accel_bytes[4]};
    
    // SPI transaction control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_active <= 1'b0;
            spi_data_out <= 8'h00;
            spi_bit_count <= 5'd0;
            byte_count <= 8'd0;
            byte_idx <= 3'd0;
        end else begin
            case (state)
                IDLE: begin
                    spi_active <= 1'b0;
                    spi_bit_count <= 5'd0;
                    byte_count <= 8'd0;
                end
                
                START_READ_DATA: begin
                    spi_active <= 1'b1;
                    // Read 6 bytes starting from DATAX0 register (0x32)
                    // Address byte: bit 7=1 (read), bit 6=1 (multi-byte), bits 5:0=register
                    spi_data_out <= {1'b1, 1'b1, DATAX0_REG[5:0]};
                    spi_bit_count <= 5'd8;
                    byte_count <= 8'd0;
                end
                
                READ_ACCEL_DATA: begin
                    if (clk_div == 6'd0) begin
                        if (spi_bit_count > 0) begin
                            spi_data_out <= {spi_data_out[6:0], 1'b0};
                            accel_bytes[byte_idx] <= {accel_bytes[byte_idx][6:0], spi_miso};
                            spi_bit_count <= spi_bit_count - 1;
                        end else begin
                            // Byte complete
                            if (byte_count < 8'd5) begin
                                byte_count <= byte_count + 1;
                                byte_idx <= byte_idx + 1;
                                spi_bit_count <= 5'd8;
                                spi_data_out <= 8'h00;
                            end else begin
                                // All 6 bytes received
                                spi_active <= 1'b0;
                            end
                        end
                    end
                end
                
                COLLECT_DATA: begin
                    // Data already assembled in accel_x, accel_y, accel_z
                end
                
                DONE: begin
                    // Hold valid signal for one cycle
                end
                
                default: begin
                    spi_active <= 1'b0;
                end
            endcase
        end
    end
    
    // SPI clock enable (always running for simplicity, gated by spi_active)
    assign spi_clk_en = spi_active || (state == START_READ_DATA);

endmodule
