// rom_sync — synchrones ROM, Inhalt aus einer Hex-Datei.
//
// Zweck:  Festwertspeicher als Block-RAM. INIT_FILE enthält ein Byte pro
//         Zeile in Hex-Schreibweise ($readmemh) und wird von Simulation und
//         Quartus gleichermaßen gelesen.
// Takt:   clk; gelesen wird nur bei en = 1 (Taktfreigabe).
// Ports:  addr -> dout_q, eine Taktflanke verzögert.

`default_nettype none

module rom_sync #(
    parameter ADDR_W    = 13,
    parameter DATA_W    = 8,
    parameter INIT_FILE = ""
) (
    input  wire              clk,
    input  wire              en,
    input  wire [ADDR_W-1:0] addr,
    output reg  [DATA_W-1:0] dout_q
);

    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    initial $readmemh(INIT_FILE, mem);

    always @(posedge clk) begin
        if (en) dout_q <= mem[addr];
    end

endmodule

`default_nettype wire
