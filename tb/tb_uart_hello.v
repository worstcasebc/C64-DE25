// tb_uart_hello — selbstprüfende Testbench für uart_hello (zusammen mit uart_tx).
//
// Prüft:
//   1. Ohne start wird nichts gesendet.
//   2. Eine steigende Flanke von start sendet genau den erwarteten Text.
//   3. Bleibt start auf 1, wird der Text nicht wiederholt.
//   4. Eine zweite Flanke sendet den Text erneut.

`timescale 1ns / 1ps
`default_nettype none

module tb_uart_hello;

    localparam CLKS_PER_BIT = 4;
    localparam BIT_NS       = CLKS_PER_BIT * 20;
    localparam LEN          = 20;
    localparam [8*LEN-1:0] EXPECTED = "DE25-Nano: UART ok\015\n";

    reg        clk   = 1'b0;
    reg        rst   = 1'b1;
    reg        start = 1'b0;
    wire [7:0] tx_data;
    wire       tx_valid;
    wire       tx_ready;
    wire       txd;

    integer errors = 0;
    integer starts = 0;   // Anzahl gesehener Startbits

    uart_hello dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .tx_ready (tx_ready)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart_tx (
        .clk   (clk),
        .rst   (rst),
        .data  (tx_data),
        .valid (tx_valid),
        .ready (tx_ready),
        .txd_q (txd)
    );

    always #10 clk = ~clk;   // 50 MHz

    task recv_byte(output [7:0] value);
        integer i;
        begin
            @(negedge txd);
            starts = starts + 1;
            #(BIT_NS / 2);
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_NS);
                value[i] = txd;
            end
            #(BIT_NS);
            if (txd !== 1'b1) begin
                $display("FAIL: Stoppbit nicht 1 bei t=%0t", $time);
                errors = errors + 1;
            end
        end
    endtask

    task expect_message;
        integer   n;
        reg [7:0] got;
        reg [7:0] want;
        begin
            for (n = 0; n < LEN; n = n + 1) begin
                recv_byte(got);
                want = EXPECTED[8*(LEN-1-n) +: 8];
                if (got !== want) begin
                    $display("FAIL: Zeichen %0d ist %h, erwartet %h", n, got, want);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_uart_hello.vcd");
        $dumpvars(0, tb_uart_hello);

        repeat (3) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 1. Ruhe ohne start
        #(20 * BIT_NS);
        if (txd !== 1'b1 || tx_valid !== 1'b0) begin
            $display("FAIL: Aktivitaet ohne start");
            errors = errors + 1;
        end

        // 2. Erste Flanke
        @(negedge clk) start = 1'b1;
        expect_message;

        // 3. start bleibt 1: keine Wiederholung
        #(30 * BIT_NS);
        if (txd !== 1'b1 || tx_valid !== 1'b0) begin
            $display("FAIL: Text wird bei gehaltenem start wiederholt");
            errors = errors + 1;
        end

        // 4. Zweite Flanke
        @(negedge clk) start = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk) start = 1'b1;
        expect_message;
        #(15 * BIT_NS);

        if (starts !== 2 * LEN) begin
            $display("FAIL: %0d Bytes gesendet, erwartet %0d", starts, 2 * LEN);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: tb_uart_hello");
        else             $display("FAIL: tb_uart_hello (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: tb_uart_hello Timeout");
        $finish;
    end

endmodule

`default_nettype wire
