// ram_2clk — Block-RAM mit einem Schreib- und einem Lese-Anschluss an zwei
//            verschiedenen Takten.
//
// Zweck:  Übergabe größerer Datenmengen zwischen zwei Taktdomänen. Die eine
//         Seite schreibt mit ihrem Takt hinein, die andere liest mit ihrem
//         heraus — wie ein Regal mit einer Tür auf jeder Seite der Wand. Das
//         RAM selbst ist dabei der Übergang; es braucht keinen Synchronizer,
//         solange nicht dieselbe Zelle im selben Augenblick beschrieben und
//         gelesen wird. Dafür sorgt der Benutzer: Erst schreibt die eine
//         Seite alles, dann meldet sie es (über einen eigenen, synchroni-
//         sierten Weg), dann liest die andere.
// Takte:  wr_clk für den Schreib-, rd_clk für den Lese-Anschluss. Kein Reset.
// Ports:  wr_en = 1 schreibt wr_din nach wr_addr.
//         Lesedaten erscheinen eine Flanke von rd_clk nach rd_addr.
// Inhalt: Beim Start überall 0 — wie das Block-RAM im FPGA nach dem Laden.
// Parameter: DEPTH — Anzahl der Zellen, falls es weniger als 2^ADDR_W sein
//         sollen (spart Block-RAM, wenn die Größe keine Zweierpotenz ist).

`default_nettype none

module ram_2clk #(
    parameter ADDR_W = 11,
    parameter DATA_W = 8,
    parameter DEPTH  = 1 << ADDR_W
) (
    input  wire              wr_clk,
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [DATA_W-1:0] wr_din,
    input  wire              rd_clk,
    input  wire [ADDR_W-1:0] rd_addr,
    output reg  [DATA_W-1:0] rd_dout_q
);

    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // Nur für die Simulation; Quartus überspringt den Abschnitt.
    // synthesis translate_off
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = {DATA_W{1'b0}};
    end
    // synthesis translate_on

    always @(posedge wr_clk) begin
        if (wr_en) mem[wr_addr] <= wr_din;
    end

    always @(posedge rd_clk) begin
        rd_dout_q <= mem[rd_addr];
    end

endmodule

`default_nettype wire
