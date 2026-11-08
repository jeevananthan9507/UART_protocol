`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// uart_rx : UART receiver, 8 data bits, 1 stop bit, optional parity
//   - 2-flop synchronizer on rx (asynchronous input)
//   - start bit confirmed at mid-bit (glitches rejected)
//   - each bit sampled at its middle
//   - rx_valid pulses for 1 clock when a frame finished; rx_data, frame_err and
//     parity_err are valid in that same cycle (data is delivered even if flagged)
//   - receiver re-arms only after the line has been seen HIGH, so a break
//     condition or bad stop bit does not cause false start bits
// -----------------------------------------------------------------------------
module uart_rx #(
    parameter CLK_FREQ   = 100_000_000,
    parameter BAUD       = 9600,
    parameter PARITY_EN  = 0,
    parameter PARITY_ODD = 0
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        frame_err,    // stop bit sampled as 0
    output reg        parity_err    // parity mismatch (always 0 if PARITY_EN=0)
);
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;
    localparam integer HALF         = CLKS_PER_BIT / 2;
    localparam [2:0] IDLE = 3'd0, START = 3'd1, DATA = 3'd2, PARITY = 3'd3, STOP = 3'd4;

    reg rx_s1, rx_s2;
    always @(posedge clk) begin
        if (rst) begin rx_s1 <= 1'b1; rx_s2 <= 1'b1; end
        else     begin rx_s1 <= rx;   rx_s2 <= rx_s1; end
    end

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;
    reg        p_err;
    reg        armed;               // line has been high since the last frame

    wire bit_done = (clk_cnt == CLKS_PER_BIT - 1);
    wire exp_par  = (^shreg) ^ (PARITY_ODD ? 1'b1 : 1'b0);

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; clk_cnt <= 0; bit_idx <= 0; shreg <= 0; p_err <= 0; armed <= 0;
            rx_data <= 0; rx_valid <= 0; frame_err <= 0; parity_err <= 0;
        end else begin
            rx_valid <= 1'b0;
            case (state)
                IDLE: begin
                    clk_cnt <= 0; bit_idx <= 0;
                    if (rx_s2) armed <= 1'b1;
                    else if (armed) begin armed <= 1'b0; state <= START; end
                end
                START: begin                                  // wait half a bit
                    if (clk_cnt == HALF - 1) begin
                        clk_cnt <= 0;
                        if (!rx_s2) state <= DATA;            // real start bit
                        else        state <= IDLE;            // glitch
                    end else clk_cnt <= clk_cnt + 1;
                end
                DATA: begin
                    if (bit_done) begin
                        clk_cnt <= 0;
                        shreg[bit_idx] <= rx_s2;              // LSB first
                        if (bit_idx == 7) state <= (PARITY_EN ? PARITY : STOP);
                        else bit_idx <= bit_idx + 1;
                    end else clk_cnt <= clk_cnt + 1;
                end
                PARITY: begin
                    if (bit_done) begin
                        clk_cnt <= 0;
                        p_err   <= (rx_s2 != exp_par);
                        state   <= STOP;
                    end else clk_cnt <= clk_cnt + 1;
                end
                STOP: begin
                    if (bit_done) begin
                        clk_cnt    <= 0;
                        state      <= IDLE;
                        rx_data    <= shreg;
                        frame_err  <= ~rx_s2;
                        parity_err <= PARITY_EN ? p_err : 1'b0;
                        rx_valid   <= 1'b1;
                    end else clk_cnt <= clk_cnt + 1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
