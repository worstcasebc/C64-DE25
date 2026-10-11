// ram_dp_sync — synchrones RAM mit zweitem Lese-Anschluss (Block-RAM).
//
// Zweck:  Wie ram_sync, aber mit zwei Türen zur selben Bibliothek:
//         Anschluss A liest und schreibt (CPU), Anschluss B liest nur
//         (Video). Beide arbeiten unabhängig mit eigener Adresse.
// Takt:   clk für beide Anschlüsse; jeder hat eine eigene Lesefreigabe.
// Ports:  a_we = 1 schreibt a_din nach a_addr — unabhängig von a_en. So
//         kann jemand über Anschluss A schreiben, ohne dass sich dessen
//         Leseausgang ändert (siehe DMA in soc_c64).
//         a_en/b_en = 1: Lesedaten erscheinen eine Flanke nach der Adresse.
//         Wird eine Zelle im selben Takt beschrieben und gelesen, liefern
//         beide Anschlüsse noch den alten Inhalt.
// Inhalt: Beim Start überall 0 — wie das Block-RAM im FPGA nach dem Laden.
//         Ohne diese Angabe wäre der Inhalt in der Simulation unbestimmt.

`default_nettype none

module ram_dp_sync #(
    parameter ADDR_W = 16,
    parameter DATA_W = 8
) (
    input  wire              clk,
    input  wire              a_en,
    input  wire              a_we,
    input  wire [ADDR_W-1:0] a_addr,
    input  wire [DATA_W-1:0] a_din,
    output reg  [DATA_W-1:0] a_dout_q,
    input  wire              b_en,
    input  wire [ADDR_W-1:0] b_addr,
    output reg  [DATA_W-1:0] b_dout_q
);

    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    // Nur für die Simulation; Quartus überspringt den Abschnitt.
    // synthesis translate_off
    integer i;
    initial begin
        for (i = 0; i < (1 << ADDR_W); i = i + 1) mem[i] = {DATA_W{1'b0}};
    end
    // synthesis translate_on

    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_din;
        if (a_en) a_dout_q <= mem[a_addr];
    end

    always @(posedge clk) begin
        if (b_en) b_dout_q <= mem[b_addr];
    end

endmodule

`default_nettype wire
