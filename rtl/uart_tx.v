`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// uart_tx : UART transmitter, 8 data bits, 1 stop bit, optional parity
//   PARITY_EN  : 0 = no parity (8N1), 1 = parity bit sent after D7
//   PARITY_ODD : 0 = even parity,      1 = odd parity   (used only if PARITY_EN=1)
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter CLK_FREQ   = 100_000_000,
    parameter BAUD       = 9600,
    parameter PARITY_EN  = 0,
    parameter PARITY_ODD = 0
)(
    input  wire       clk,
    input  wire       rst,          // synchronous, active high
    input  wire       tx_start,     // pulse for 1 clock to send tx_data
    input  wire [7:0] tx_data,
    output reg        tx,           // serial output, idles HIGH
    output reg        busy
);
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;
    localparam [2:0] IDLE = 3'd0, START = 3'd1, DATA = 3'd2, PARITY = 3'd3, STOP = 3'd4;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_reg;

    // ^data_reg = 1 when the number of 1s is odd.
    // even parity bit = ^data ; odd parity bit = ~^data
    wire parity_bit = (^data_reg) ^ (PARITY_ODD ? 1'b1 : 1'b0);

    wire bit_done = (clk_cnt == CLKS_PER_BIT - 1);

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; tx <= 1'b1; busy <= 1'b0;
            clk_cnt <= 0; bit_idx <= 0; data_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1; busy <= 1'b0; clk_cnt <= 0; bit_idx <= 0;
                    if (tx_start) begin
                        data_reg <= tx_data; busy <= 1'b1; state <= START;
                    end
                end
                START: begin
                    tx <= 1'b0;
                    if (bit_done) begin clk_cnt <= 0; state <= DATA; end
                    else clk_cnt <= clk_cnt + 1;
                end
                DATA: begin
                    tx <= data_reg[bit_idx];                 // LSB first
                    if (bit_done) begin
                        clk_cnt <= 0;
                        if (bit_idx == 7) state <= (PARITY_EN ? PARITY : STOP);
                        else bit_idx <= bit_idx + 1;
                    end else clk_cnt <= clk_cnt + 1;
                end
                PARITY: begin
                    tx <= parity_bit;
                    if (bit_done) begin clk_cnt <= 0; state <= STOP; end
                    else clk_cnt <= clk_cnt + 1;
                end
                STOP: begin
                    tx <= 1'b1;
                    if (bit_done) begin clk_cnt <= 0; state <= IDLE; end
                    else clk_cnt <= clk_cnt + 1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
