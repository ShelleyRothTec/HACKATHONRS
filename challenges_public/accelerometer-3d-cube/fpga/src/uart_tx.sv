module uart_tx (
    input           clk,
    input           rst_n,
    input           start,          // Start sending data
    output          busy,           // High while transmitting
    output          tx,             // Serial output
    
    // Data to send (6 bytes for X, Y, Z acceleration)
    input   [7:0]   byte0,
    input   [7:0]   byte1,
    input   [7:0]   byte2,
    input   [7:0]   byte3,
    input   [7:0]   byte4,
    input   [7:0]   byte5
);

    // UART parameters: 9600 baud, 8N1
    // For 50 MHz clock: clock periods per bit = 50,000,000 / 9600 = 5208
    localparam CLK_PER_BIT = 16'd5208;
    
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT,
        INTER_BYTE_DELAY
    } state_t;
    
    state_t state, next_state;
    
    logic [15:0] clk_count;
    logic [2:0] bit_count;
    logic [7:0] byte_count;
    logic [7:0] current_byte;
    logic [7:0] bytes [5:0];
    
    // Mux to select current byte
    always_comb begin
        case (byte_count)
            3'd0: current_byte = bytes[0];
            3'd1: current_byte = bytes[1];
            3'd2: current_byte = bytes[2];
            3'd3: current_byte = bytes[3];
            3'd4: current_byte = bytes[4];
            3'd5: current_byte = bytes[5];
            default: current_byte = 8'h00;
        endcase
    end
    
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
                    next_state = START_BIT;
            end
            START_BIT: begin
                if (clk_count == CLK_PER_BIT - 1)
                    next_state = DATA_BITS;
            end
            DATA_BITS: begin
                if (bit_count == 3'd7 && clk_count == CLK_PER_BIT - 1)
                    next_state = STOP_BIT;
            end
            STOP_BIT: begin
                if (clk_count == CLK_PER_BIT - 1) begin
                    if (byte_count == 3'd5)
                        next_state = IDLE;
                    else
                        next_state = INTER_BYTE_DELAY;
                end
            end
            INTER_BYTE_DELAY: begin
                if (clk_count == CLK_PER_BIT - 1)
                    next_state = START_BIT;
            end
            default: next_state = IDLE;
        endcase
    end
    
    // Counter and state control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_count <= 16'h0000;
            bit_count <= 3'd0;
            byte_count <= 3'd0;
            bytes[0] <= 8'h00;
            bytes[1] <= 8'h00;
            bytes[2] <= 8'h00;
            bytes[3] <= 8'h00;
            bytes[4] <= 8'h00;
            bytes[5] <= 8'h00;
        end else begin
            if (state == IDLE) begin
                clk_count <= 16'h0000;
                bit_count <= 3'd0;
                byte_count <= 3'd0;
                if (start) begin
                    bytes[0] <= byte0;
                    bytes[1] <= byte1;
                    bytes[2] <= byte2;
                    bytes[3] <= byte3;
                    bytes[4] <= byte4;
                    bytes[5] <= byte5;
                end
            end else begin
                if (clk_count == CLK_PER_BIT - 1) begin
                    clk_count <= 16'h0000;
                    if (state == DATA_BITS)
                        bit_count <= bit_count + 1;
                    else if (state == STOP_BIT)
                        byte_count <= byte_count + 1;
                end else begin
                    clk_count <= clk_count + 1;
                end
            end
        end
    end
    
    // TX output logic
    assign tx = (state == START_BIT) ? 1'b0 :
                (state == DATA_BITS) ? current_byte[bit_count] :
                (state == STOP_BIT || state == IDLE || state == INTER_BYTE_DELAY) ? 1'b1 :
                1'b1;
    
    assign busy = (state != IDLE);

endmodule
