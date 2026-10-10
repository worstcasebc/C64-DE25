// ram_sync — synchrones RAM (wird von Quartus als Block-RAM erkannt).
//
// Zweck:  Speicher mit getaktetem Lesen: Die Adresse wird an der Taktflanke
//         übernommen, die Daten liegen danach an dout_q an (wie ein
//         Bibliothekar, der erst im nächsten Schritt mit dem Buch zurückkommt).
// Takt:   clk; es passiert nur etwas, wenn en = 1 ist (Taktfreigabe).
// Ports:  we = 1 schreibt din nach addr. dout_q liefert bei gleichzeitigem
//         Schreiben noch den alten Inhalt.

`default_nettype none

module ram_sync #(
    parameter ADDR_W = 15,
    parameter DATA_W = 8
) (
    input  wire              clk,
    input  wire              en,
    input  wire              we,
    input  wire [ADDR_W-1:0] addr,
    input  wire [DATA_W-1:0] din,
    output reg  [DATA_W-1:0] dout_q
);

    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    always @(posedge clk) begin
        if (en) begin
            if (we) mem[addr] <= din;
            dout_q <= mem[addr];
        end
    end

endmodule

`default_nettype wire
