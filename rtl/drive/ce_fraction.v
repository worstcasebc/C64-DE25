// ce_fraction — Taktfreigabe in einem festen Bruchteil der Takte.
//
// Zweck:  Macht aus einem schnellen Takt eine langsamere Freigabe, deren
//         Verhältnis kein glatter Teiler sein muss: ce_q ist in NUM von DEN
//         Takten 1, möglichst gleichmäßig verteilt. Für das Laufwerk 1541
//         (rechnet mit 16 MHz) am Systemtakt 31,5 MHz sind das 32 von 63.
//         Wie ein Metronom, das ab und zu einen Schlag auslässt: In jedem
//         Takt kommen NUM auf ein Konto; ist DEN erreicht, gibt es eine
//         Freigabe, und DEN wird abgezogen. Der Rest bleibt stehen, so geht
//         auf Dauer nichts verloren.
// Takt:   clk, synchroner Reset rst (aktiv high).
// Ports:  ce_q = 1 für einen Takt pro Freigabe. Verlangt 0 < NUM <= DEN.

`default_nettype none

module ce_fraction #(
    parameter NUM = 32,
    parameter DEN = 63
) (
    input  wire clk,
    input  wire rst,
    output reg  ce_q
);

    localparam ACC_W = $clog2(NUM + DEN);

    reg  [ACC_W-1:0] acc_q;
    wire [ACC_W-1:0] sum = acc_q + NUM[ACC_W-1:0];

    always @(posedge clk) begin
        if (rst) begin
            acc_q <= {ACC_W{1'b0}};
            ce_q  <= 1'b0;
        end else if (sum >= DEN[ACC_W-1:0]) begin
            acc_q <= sum - DEN[ACC_W-1:0];
            ce_q  <= 1'b1;
        end else begin
            acc_q <= sum;
            ce_q  <= 1'b0;
        end
    end

endmodule

`default_nettype wire
