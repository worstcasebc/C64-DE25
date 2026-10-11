// uart_rx_check — Hilfsmodul für Testbenches (nicht synthetisierbar).
//
// Einfacher UART-Empfänger: liest LEN Bytes (8N1, BIT_NS Nanosekunden pro
// Bit) und vergleicht sie mit EXPECTED. done = 1, wenn alle Bytes da sind;
// errors zählt Abweichungen.

`timescale 1ns / 1ps
`default_nettype none

module uart_rx_check #(
    parameter               BIT_NS   = 80,
    parameter               LEN      = 1,
    parameter [8*LEN-1:0]   EXPECTED = 0
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

`default_nettype wire
