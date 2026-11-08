`timescale 1ns/1ps
// =============================================================================
// Self-checking testbench for the UART
//   tb_loopback  : TX -> RX loopback for one format (8N1 / 8E1 / 8O1)
//                  fixed bytes, random bytes, back-to-back bytes
//   tb_rx_errors : drives the receiver directly with hand-made frames to
//                  verify error detection (bad stop bit, bad parity, glitch,
//                  break condition) and recovery afterwards
//   tb_uart      : top; runs 3 loopback + 3 error benches in parallel
// Simulation uses 10 clocks per bit (1 MHz clock, 100 kbaud) to stay short.
// =============================================================================

module tb_loopback #(
    parameter PARITY_EN = 0, parameter PARITY_ODD = 0, parameter NAME = "8N1"
)(
    input  wire        clk,
    output reg         done,
    output reg  [31:0] errors
);
    localparam CLK_FREQ = 1_000_000, BAUD = 100_000;

    reg rst = 1, tx_start = 0;
    reg  [7:0] tx_data = 0;
    wire tx, tx_busy, rx_valid, frame_err, parity_err;
    wire [7:0] rx_data;

    uart_top #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD),
               .PARITY_EN(PARITY_EN), .PARITY_ODD(PARITY_ODD)) dut (
        .clk(clk), .rst(rst), .tx_start(tx_start), .tx_data(tx_data),
        .tx(tx), .tx_busy(tx_busy),
        .rx(tx),                                     // loopback
        .rx_data(rx_data), .rx_valid(rx_valid),
        .frame_err(frame_err), .parity_err(parity_err));

    task send_and_check(input [7:0] d, input integer gap);
        begin
            @(posedge clk); tx_data <= d; tx_start <= 1'b1;
            @(posedge clk); tx_start <= 1'b0;
            @(posedge rx_valid);
            if (rx_data === d && frame_err === 1'b0 && parity_err === 1'b0)
                $display("[%0s] PASS: sent %h, received %h", NAME, d, rx_data);
            else begin
                $display("[%0s] FAIL: sent %h, received %h (frame_err=%b parity_err=%b)",
                         NAME, d, rx_data, frame_err, parity_err);
                errors = errors + 1;
            end
            wait (!tx_busy);
            repeat (gap) @(posedge clk);
        end
    endtask

    integer i;
    initial begin
        done = 0; errors = 0;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);
        // fixed patterns
        send_and_check(8'hA5, 20);
        send_and_check(8'h41, 20);
        send_and_check(8'h00, 20);
        send_and_check(8'hFF, 20);
        send_and_check(8'h55, 20);
        // random data
        for (i = 0; i < 20; i = i + 1) send_and_check($random, 20);
        // back-to-back (no idle gap between frames)
        for (i = 0; i < 5; i = i + 1) send_and_check($random, 0);
        done = 1;
    end
endmodule


module tb_rx_errors #(
    parameter PARITY_EN = 1, parameter PARITY_ODD = 0, parameter NAME = "8E1"
)(
    input  wire        clk,
    output reg         done,
    output reg  [31:0] errors
);
    localparam CLK_FREQ = 1_000_000, BAUD = 100_000, CPB = 10;

    reg rst = 1, rx = 1;
    wire [7:0] rx_data;
    wire rx_valid, frame_err, parity_err;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD),
              .PARITY_EN(PARITY_EN), .PARITY_ODD(PARITY_ODD)) dut (
        .clk(clk), .rst(rst), .rx(rx),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .frame_err(frame_err), .parity_err(parity_err));

    // monitor: capture what the receiver reports
    integer    n_valid = 0;
    reg [7:0]  got_data = 0;
    reg        got_f = 0, got_p = 0;
    always @(posedge clk) if (rx_valid) begin
        n_valid  <= n_valid + 1;
        got_data <= rx_data;
        got_f    <= frame_err;
        got_p    <= parity_err;
    end

    task drive_bit(input b);
        begin rx <= b; repeat (CPB) @(posedge clk); end
    endtask

    // one frame; par_flip=1 corrupts parity, stop_val=0 corrupts the stop bit
    task drive_frame(input [7:0] d, input par_flip, input stop_val);
        reg p; integer k;
        begin
            p = (^d) ^ (PARITY_ODD ? 1'b1 : 1'b0) ^ par_flip;
            drive_bit(1'b0);                                  // start
            for (k = 0; k < 8; k = k + 1) drive_bit(d[k]);    // data, LSB first
            if (PARITY_EN) drive_bit(p);
            drive_bit(stop_val);
            drive_bit(1'b1);                                  // idle
            drive_bit(1'b1);
        end
    endtask

    task check(input [511:0] what, input cond);
        begin
            if (cond) $display("[%0s] PASS: %0s", NAME, what);
            else begin $display("[%0s] FAIL: %0s", NAME, what); errors = errors + 1; end
        end
    endtask

    initial begin
        done = 0; errors = 0;
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        // 1. good frame
        n_valid = 0;
        drive_frame(8'h3C, 1'b0, 1'b1);
        check("good frame accepted, no flags",
              n_valid == 1 && got_data == 8'h3C && !got_f && !got_p);

        // 2. bad stop bit -> framing error
        n_valid = 0;
        drive_frame(8'hC3, 1'b0, 1'b0);
        check("bad stop bit gives frame_err",
              n_valid == 1 && got_data == 8'hC3 && got_f && !got_p);

        // 3. bad parity -> parity error (only when parity enabled)
        if (PARITY_EN) begin
            n_valid = 0;
            drive_frame(8'h5A, 1'b1, 1'b1);
            check("bad parity gives parity_err",
                  n_valid == 1 && got_data == 8'h5A && got_p && !got_f);
        end

        // 4. glitch shorter than half a bit is ignored
        n_valid = 0;
        rx <= 1'b0; repeat (3) @(posedge clk);
        rx <= 1'b1; repeat (6 * CPB) @(posedge clk);
        check("short glitch ignored", n_valid == 0);

        // 5. recovery: good frame after errors
        n_valid = 0;
        drive_frame(8'hA7, 1'b0, 1'b1);
        check("good frame after errors",
              n_valid == 1 && got_data == 8'hA7 && !got_f && !got_p);

        // 6. break: line held low for several frames -> one framed byte, no false starts
        n_valid = 0;
        rx <= 1'b0; repeat (40 * CPB) @(posedge clk);
        rx <= 1'b1; repeat (3 * CPB) @(posedge clk);
        check("break reported once with frame_err",
              n_valid == 1 && got_data == 8'h00 && got_f);

        // 7. recovery after break
        n_valid = 0;
        drive_frame(8'h96, 1'b0, 1'b1);
        check("good frame after break",
              n_valid == 1 && got_data == 8'h96 && !got_f && !got_p);

        done = 1;
    end
endmodule


module tb_uart;
    reg clk = 0;
    always #5 clk = ~clk;

    wire d0, d1, d2, d3, d4, d5;
    wire [31:0] e0, e1, e2, e3, e4, e5;

    tb_loopback  #(0, 0, "8N1") t0 (.clk(clk), .done(d0), .errors(e0));
    tb_loopback  #(1, 0, "8E1") t1 (.clk(clk), .done(d1), .errors(e1));
    tb_loopback  #(1, 1, "8O1") t2 (.clk(clk), .done(d2), .errors(e2));
    tb_rx_errors #(0, 0, "8N1 errors") t3 (.clk(clk), .done(d3), .errors(e3));
    tb_rx_errors #(1, 0, "8E1 errors") t4 (.clk(clk), .done(d4), .errors(e4));
    tb_rx_errors #(1, 1, "8O1 errors") t5 (.clk(clk), .done(d5), .errors(e5));

    initial begin
        wait (d0 && d1 && d2 && d3 && d4 && d5);
        #100;
        if ((e0 + e1 + e2 + e3 + e4 + e5) == 0) $display("ALL TESTS PASSED");
        else $display("TESTS FAILED: %0d error(s)", e0 + e1 + e2 + e3 + e4 + e5);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TIMEOUT: simulation hung");
        $finish;
    end

    initial begin
        $dumpfile("uart_wave.vcd");
        $dumpvars(0, tb_uart);
    end
endmodule
