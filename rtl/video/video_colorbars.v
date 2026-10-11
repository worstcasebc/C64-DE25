// video_colorbars — Testbild: acht Farbbalken mit weißem Rand.
//
// Zweck:  Board-Test für den Videopfad, noch ohne C64. Acht senkrechte
//         Balken zu je 80 Pixeln: Weiß, Gelb, Cyan, Grün, Magenta, Rot,
//         Blau, Schwarz. Die äußerste Pixelreihe rundum ist weiß — fehlt am
//         Monitor eine Kante, ist das Bild verschoben oder abgeschnitten.
// Takt:   clk; es passiert nur etwas, wenn en = 1 ist (Pixeltakt-Freigabe).
// Ports:  x, y, de, hsync, vsync kommen von video_timing. Die Ausgänge sind
//         Register: Farbe und die drei Steuersignale erscheinen gemeinsam
//         einen Pixeltakt später, bleiben also zueinander ausgerichtet.
//         Außerhalb des sichtbaren Bereichs ist die Farbe Schwarz.

`default_nettype none

module video_colorbars #(
    parameter H_ACTIVE = 640,
    parameter V_ACTIVE = 480
) (
    input  wire        clk,
    input  wire        en,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    input  wire        hsync,
    input  wire        vsync,
    output reg  [7:0]  r_q,
    output reg  [7:0]  g_q,
    output reg  [7:0]  b_q,
    output reg         de_q,
    output reg         hsync_q,
    output reg         vsync_q
);

    localparam BAR_W = H_ACTIVE / 8;

    // Balkennummer 0..7 = Anzahl der überschrittenen Balkengrenzen.
    wire [2:0] bar = (x >= 1 * BAR_W) + (x >= 2 * BAR_W) + (x >= 3 * BAR_W)
                   + (x >= 4 * BAR_W) + (x >= 5 * BAR_W) + (x >= 6 * BAR_W)
                   + (x >= 7 * BAR_W);

    wire border = (x == 0) || (x == H_ACTIVE - 1) || (y == 0) || (y == V_ACTIVE - 1);

    // Die klassische Balkenfolge ergibt sich direkt aus den Bits der Nummer.
    wire red   = border | ~bar[1];
    wire green = border | ~bar[2];
    wire blue  = border | ~bar[0];

    always @(posedge clk) begin
        if (en) begin
            r_q     <= {8{de & red}};
            g_q     <= {8{de & green}};
            b_q     <= {8{de & blue}};
            de_q    <= de;
            hsync_q <= hsync;
            vsync_q <= vsync;
        end
    end

endmodule

`default_nettype wire
