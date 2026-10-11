// audio_boxcar — glättet das Tonsignal durch Mittelwertbildung.
//
// Zweck:  Der SID liefert rund eine Million Werte pro Sekunde, über HDMI
//         gehen aber nur 48000. Würde man einfach jeden zwanzigsten Wert
//         nehmen, landeten hohe Töne als Störgeräusche im hörbaren Bereich
//         (so wie sich Wagenräder im Film scheinbar rückwärts drehen).
//         Dieses Modul bildet deshalb fortlaufend den Mittelwert über je 16
//         aufeinanderfolgende Werte — ein einfacher Tiefpass.
// Takt:   clk, synchroner Reset rst (aktiv high).
// Ports:  in/in_valid — Eingangswert mit Vorzeichen, gültig bei
//         in_valid = 1 (einmal pro CPU-Takt).
//         out_q — Mittelwert der letzten abgeschlossenen 16er-Gruppe.

`default_nettype none

module audio_boxcar #(
    parameter W = 18
) (
    input  wire                clk,
    input  wire                rst,
    input  wire signed [W-1:0] in,
    input  wire                in_valid,
    output reg  signed [W-1:0] out_q
);

    reg signed [W+3:0] sum_q;       // Summe von bis zu 16 Werten
    reg        [3:0]   n_q;

    wire signed [W+3:0] sum_next = sum_q + in;

    always @(posedge clk) begin
        if (rst) begin
            sum_q <= {(W+4){1'b0}};
            n_q   <= 4'd0;
            out_q <= {W{1'b0}};
        end else if (in_valid) begin
            n_q <= n_q + 1'b1;
            if (n_q == 4'd15) begin
                out_q <= sum_next[W+3:4];   // durch 16 teilen
                sum_q <= {(W+4){1'b0}};
            end else begin
                sum_q <= sum_next;
            end
        end
    end

endmodule

`default_nettype wire
