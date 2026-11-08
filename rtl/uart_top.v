`timescale 1ns/1ps
// uart_top : one transmitter + one receiver sharing clock, reset and settings
module uart_top #(
    parameter CLK_FREQ   = 100_000_000,
    parameter BAUD       = 9600,
    parameter PARITY_EN  = 0,
    parameter PARITY_ODD = 0
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output wire       tx,
    output wire       tx_busy,
    input  wire       rx,
    output wire [7:0] rx_data,
    output wire       rx_valid,
    output wire       frame_err,
    output wire       parity_err
);
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD), .PARITY_EN(PARITY_EN), .PARITY_ODD(PARITY_ODD)) u_tx (
        .clk(clk), .rst(rst), .tx_start(tx_start), .tx_data(tx_data), .tx(tx), .busy(tx_busy));

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD), .PARITY_EN(PARITY_EN), .PARITY_ODD(PARITY_ODD)) u_rx (
        .clk(clk), .rst(rst), .rx(rx),
        .rx_data(rx_data), .rx_valid(rx_valid), .frame_err(frame_err), .parity_err(parity_err));
endmodule
