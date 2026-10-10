// tb_soc_mini — selbstprüfende Testbench für das Mini-System.
//
// Lässt das echte ROM-Programm (sw/asm/hello.s) laufen und prüft, dass am
// UART-Pin genau der erwartete Text erscheint: Begrüßung und die ersten zwei
// Zählerzeilen. Damit sind CPU, ROM, RAM (Zeropage, Stack), Address-Decoder
// und UART-Register gemeinsam getestet.
//
// Zwei Instanzen laufen parallel: CPU_DIV = 1 (CPU in jedem Takt) und
// CPU_DIV = 3 (Taktfreigabe jeden dritten Takt). Beide müssen denselben Text
// liefern — das prüft, dass die Taktfreigabe das Verhalten nicht verändert.
//
// Hinweis: Die Warteschleife im Programm macht den Test etwas länger
// (rund eine Million Takte).

`timescale 1ns / 1ps
`default_nettype none

// Einfacher UART-Empfänger: liest LEN Bytes und vergleicht sie mit EXPECTED.
module uart_rx_check #(
    parameter               BIT_NS   = 80,
    parameter               LEN      = 1,
    parameter [8*59-1:0]    EXPECTED = 0
) (
    input  wire        rxd,
    output reg         done,
    output reg  [31:0] errors
);
    integer   n;
    integer   i;
    reg [7:0] got;
    reg [7:0] want;

    initial begin
        done   = 1'b0;
        errors = 0;
        for (n = 0; n < LEN; n = n + 1) begin
            @(negedge rxd);
            #(BIT_NS / 2);
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_NS);
                got[i] = rxd;
            end
            #(BIT_NS);
            if (rxd !== 1'b1) begin
                $display("FAIL: %m Stoppbit fehlt bei Zeichen %0d", n);
                errors = errors + 1;
            end
            want = EXPECTED[8*(LEN-1-n) +: 8];
            if (got !== want) begin
                $display("FAIL: %m Zeichen %0d ist %h, erwartet %h ('%c')", n, got, want, want);
                errors = errors + 1;
            end
        end
        done = 1'b1;
    end
endmodule

module tb_soc_mini;

    localparam CLKS_PER_BIT = 4;
    localparam LEN          = 59;
    localparam [8*LEN-1:0] EXPECTED =
        "6502 laeuft auf dem DE25-Nano\015\nZaehler: $00\015\nZaehler: $01\015\n";

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    wire txd_div1;
    wire txd_div3;
    wire done_div1;
    wire done_div3;
    wire [31:0] errors_div1;
    wire [31:0] errors_div3;

    soc_mini #(.CPU_DIV(1), .UART_CLKS_PER_BIT(CLKS_PER_BIT)) dut_div1 (
        .clk      (clk),
        .rst      (rst),
        .uart_txd (txd_div1)
    );

    soc_mini #(.CPU_DIV(3), .UART_CLKS_PER_BIT(CLKS_PER_BIT)) dut_div3 (
        .clk      (clk),
        .rst      (rst),
        .uart_txd (txd_div3)
    );

    uart_rx_check #(.BIT_NS(CLKS_PER_BIT * 20), .LEN(LEN), .EXPECTED(EXPECTED)) rx_div1 (
        .rxd    (txd_div1),
        .done   (done_div1),
        .errors (errors_div1)
    );

    uart_rx_check #(.BIT_NS(CLKS_PER_BIT * 20), .LEN(LEN), .EXPECTED(EXPECTED)) rx_div3 (
        .rxd    (txd_div3),
        .done   (done_div3),
        .errors (errors_div3)
    );

    always #10 clk = ~clk;   // 50 MHz

    initial begin
        // Nur die ersten 0,2 ms aufzeichnen (Reset und Programmstart),
        // sonst wird die Wellenform-Datei riesig.
        $dumpfile("tb/build/tb_soc_mini.vcd");
        $dumpvars(0, tb_soc_mini);
        #200000 $dumpoff;
    end

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        wait (done_div1 && done_div3);

        if (errors_div1 + errors_div3 == 0) $display("PASS: tb_soc_mini");
        else $display("FAIL: tb_soc_mini (%0d Fehler)", errors_div1 + errors_div3);
        $finish;
    end

    initial begin
        #60_000_000;
        $display("FAIL: tb_soc_mini Timeout (div1 fertig=%b, div3 fertig=%b)", done_div1, done_div3);
        $finish;
    end

endmodule

`default_nettype wire
