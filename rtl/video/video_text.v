// video_text — Textmodus des C64: 40x25 Zeichen aus Bildschirmspeicher und
//              Char-ROM.
//
// Zweck:  Macht aus der Strahlposition von video_timing die Farbe des
//         Pixels. Das C64-Bild (320x200) wird in beide Richtungen verdoppelt
//         und liegt als 640x400 in der Mitte von 640x480; darüber und
//         darunter bleiben je V_OFFSET = 40 Zeilen Rahmen.
//         Ablauf wie ein Fließband mit drei Stationen (je ein Pixeltakt):
//           1. Aus der Position die Adresse im Bildschirmspeicher bilden
//              ($0400 + Zeile * 40 + Spalte) -> RAM liefert den Zeichencode.
//           2. Zeichencode und Pixelzeile im Zeichen bilden die Adresse im
//              Char-ROM -> ROM liefert die 8 Pixel dieser Zeile.
//           3. Das passende Bit auswählen -> Vorder- oder Hintergrundfarbe.
//         Position und Steuersignale wandern auf dem Band mit, damit am
//         Ende alles wieder zusammenpasst.
// Takt:   clk; es passiert nur etwas, wenn en = 1 ist (Pixeltakt-Freigabe).
//         RAM und ROM müssen mit derselben Freigabe lesen.
// Ports:  x, y, de, hsync, vsync kommen von video_timing. Farbe und
//         Steuersignale erscheinen gemeinsam drei Pixeltakte später.
// Vereinfachung: feste Farben (Farb-RAM und VIC-Register fehlen noch),
//         fester Bildschirmspeicher ab $0400, nur der erste Zeichensatz.

`default_nettype none

module video_text #(
    parameter [15:0] SCREEN_BASE = 16'h0400,
    parameter        V_OFFSET    = 40,
    parameter [23:0] BORDER_RGB  = 24'h6C5EB5,  // Hellblau
    parameter [23:0] BG_RGB      = 24'h352879,  // Blau
    parameter [23:0] FG_RGB      = 24'h6C5EB5   // Hellblau
) (
    input  wire        clk,
    input  wire        en,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    input  wire        hsync,
    input  wire        vsync,
    output wire [15:0] ram_addr,
    input  wire [7:0]  ram_dout,
    output wire [11:0] char_addr,
    input  wire [7:0]  char_dout,
    output reg  [7:0]  r_q,
    output reg  [7:0]  g_q,
    output reg  [7:0]  b_q,
    output reg         de_q,
    output reg         hsync_q,
    output reg         vsync_q
);

    // --- Station 1: Adresse im Bildschirmspeicher ---------------------------
    // Ein Zeichen ist 16x16 Bildpunkte groß (8x8 verdoppelt).
    localparam [11:0] V_START = V_OFFSET;   // auf die Breite von y gebracht

    wire [11:0] text_y  = y - V_START;
    wire        in_text = de && (y >= V_OFFSET) && (y < V_OFFSET + 400);
    wire [5:0]  col     = x[9:4];           // 0..39
    wire [4:0]  row     = text_y[8:4];      // 0..24
    wire [9:0]  cell_no = {row, 5'b0} + {2'b0, row, 3'b0} + {4'b0, col};  // row*40 + col

    assign ram_addr = SCREEN_BASE + {6'b0, cell_no};

    reg [2:0] line_d1_q;        // Pixelzeile im Zeichen, 0..7
    reg [2:0] px_d1_q;          // Pixelspalte im Zeichen, 0..7
    reg       in_text_d1_q;
    reg [2:0] sync_d1_q;        // {de, hsync, vsync}

    // --- Station 2: Adresse im Char-ROM -------------------------------------
    assign char_addr = {1'b0, ram_dout, line_d1_q};

    reg [2:0] px_d2_q;
    reg       in_text_d2_q;
    reg [2:0] sync_d2_q;

    // --- Station 3: Pixel auswählen -----------------------------------------
    // Bit 7 des Musters ist das linke Pixel.
    wire        pixel = char_dout[3'd7 - px_d2_q];
    wire [23:0] rgb   = !sync_d2_q[2] ? 24'h000000 :
                        !in_text_d2_q ? BORDER_RGB :
                        pixel         ? FG_RGB     : BG_RGB;

    always @(posedge clk) begin
        if (en) begin
            line_d1_q    <= text_y[3:1];
            px_d1_q      <= x[3:1];
            in_text_d1_q <= in_text;
            sync_d1_q    <= {de, hsync, vsync};

            px_d2_q      <= px_d1_q;
            in_text_d2_q <= in_text_d1_q;
            sync_d2_q    <= sync_d1_q;

            {r_q, g_q, b_q}           <= rgb;
            {de_q, hsync_q, vsync_q}  <= sync_d2_q;
        end
    end

endmodule

`default_nettype wire
