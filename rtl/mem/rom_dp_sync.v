// rom_dp_sync — synchrones ROM mit zwei Lese-Anschlüssen (Block-RAM).
//
// Zweck:  Wie rom_sync, aber zwei unabhängige Leser: Anschluss A für die
//         CPU, Anschluss B für das Video (Char-ROM).
// Takt:   clk für beide Anschlüsse; jeder hat eine eigene Taktfreigabe.
// Ports:  Adresse -> Daten, eine Taktflanke verzögert.

`default_nettype none

module rom_dp_sync #(
    parameter ADDR_W    = 12,
    parameter DATA_W    = 8,
    parameter INIT_FILE = ""
) (
    input  wire              clk,
    input  wire              a_en,
    input  wire [ADDR_W-1:0] a_addr,
    output reg  [DATA_W-1:0] a_dout_q,
    input  wire              b_en,
    input  wire [ADDR_W-1:0] b_addr,
    output reg  [DATA_W-1:0] b_dout_q
);

    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    initial $readmemh(INIT_FILE, mem);

    always @(posedge clk) begin
        if (a_en) a_dout_q <= mem[a_addr];
    end

    always @(posedge clk) begin
        if (b_en) b_dout_q <= mem[b_addr];
    end

endmodule

`default_nettype wire
