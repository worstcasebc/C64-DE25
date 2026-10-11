// cpu_port — der eingebaute I/O-Port des 6510 ($0000/$0001).
//
// Zweck:  Der 6510 unterscheidet sich vom 6502 durch einen 6-Bit-Port, dessen
//         untere drei Leitungen im C64 das Banking steuern:
//           Bit 0 LORAM, Bit 1 HIRAM, Bit 2 CHAREN (siehe c64_addr_decode).
//         $0000 = Richtungsregister (DDR): Bit = 1 heißt "Ausgang".
//         $0001 = Datenregister.
//         Eine Leitung führt den Wert aus dem Datenregister nur, wenn sie als
//         Ausgang geschaltet ist. Sonst bestimmt die Außenwelt den Pegel —
//         hier vereinfacht der feste Wert PULLUP. Nach Reset sind alle
//         Leitungen Eingänge, die Pull-ups ziehen LORAM/HIRAM/CHAREN auf 1,
//         und damit sind KERNAL (Reset-Vektor!), BASIC und I/O sichtbar.
// Takt:   clk, synchroner Reset rst (aktiv high). Buszugriffe nur bei en = 1.
// Bus:    sel = 1 bei Adresse $0000/$0001, a0 = Adressbit 0. Lesedaten liegen
//         wie beim RAM einen Schritt später an dout_q an.
//         Lesen von $0001 liefert den Pegel der Leitungen, nicht das Register.
// Vereinfachung: Kassetten-Leitungen (Bit 3-5) haben keine Funktion; Bit 6/7
//         gibt es am 6510 nicht, sie verhalten sich hier wie Eingänge mit
//         Pegel aus PULLUP.

`default_nettype none

module cpu_port #(
    parameter [7:0] PULLUP = 8'h17   // Bit 0-2 Banking, Bit 4 Kassettentaste
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       en,
    input  wire       sel,
    input  wire       we,
    input  wire       a0,
    input  wire [7:0] din,
    output reg  [7:0] dout_q,
    output wire       loram,
    output wire       hiram,
    output wire       charen
);

    reg [7:0] ddr_q;
    reg [7:0] data_q;

    // Pegel auf den Leitungen: Ausgänge aus dem Register, Eingänge von außen.
    wire [7:0] pins = (data_q & ddr_q) | (PULLUP & ~ddr_q);

    assign loram  = pins[0];
    assign hiram  = pins[1];
    assign charen = pins[2];

    always @(posedge clk) begin
        if (rst) begin
            ddr_q  <= 8'h00;
            data_q <= 8'h00;
        end else if (en && sel && we) begin
            if (a0) data_q <= din;
            else    ddr_q  <= din;
        end
    end

    always @(posedge clk) begin
        if (en) dout_q <= a0 ? pins : ddr_q;
    end

endmodule

`default_nettype wire
