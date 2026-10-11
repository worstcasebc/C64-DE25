// video_text — Textmodus des C64: 40x25 Zeichen aus Bildschirmspeicher,
//              Farb-RAM und Char-ROM.
//
// Zweck:  Macht aus der Strahlposition von video_timing die Farbe des
//         Pixels. Das C64-Bild (320x200) wird in beide Richtungen verdoppelt
//         und liegt als 640x400 in der Mitte von 640x480; darüber und
//         darunter bleiben je V_OFFSET = 40 Zeilen Rahmen.
//         Ablauf wie ein Fließband mit drei Stationen (je ein Pixeltakt):
//           1. Aus der Position die Nummer der Zelle bilden (Zeile * 40 +
//              Spalte) -> Bildschirmspeicher liefert den Zeichencode,
//              Farb-RAM die Farbe des Zeichens.
//           2. Zeichencode und Pixelzeile im Zeichen bilden die Adresse im
//              Char-ROM -> ROM liefert die 8 Pixel dieser Zeile.
//           3. Das passende Bit auswählen -> Zeichen- oder Hintergrundfarbe.
//         Position, Zeichenfarbe und Steuersignale wandern auf dem Band mit,
//         damit am Ende alles wieder zusammenpasst.
// Takt:   clk; es passiert nur etwas, wenn en = 1 ist (Pixeltakt-Freigabe).
//         Die Speicher müssen mit derselben Freigabe lesen.
// Ports:  x, y, de, hsync, vsync kommen von video_timing. Farbe und
//         Steuersignale erscheinen gemeinsam drei Pixeltakte später.
//         border_color/bg_color — Farbnummern 0..15 aus den VIC-Registern.
// Farben: Die 16 Farbnummern des C64 werden nach der Palette von "Pepto"
//         (Philip Timmermann) in RGB übersetzt.
// Vereinfachung: fester Bildschirmspeicher ab $0400, nur der erste
//         Zeichensatz, kein seitlicher Rahmen.

`default_nettype none

module video_text #(
    parameter [15:0] SCREEN_BASE = 16'h0400,
    parameter        V_OFFSET    = 40
) (
    input  wire        clk,
    input  wire        en,
    input  wire [11:0] x,
    input  wire [11:0] y,
    input  wire        de,
    input  wire        hsync,
    input  wire        vsync,
    input  wire [3:0]  border_color,
    input  wire [3:0]  bg_color,
    output wire [15:0] ram_addr,
    input  wire [7:0]  ram_dout,
    output wire [9:0]  color_addr,
    input  wire [3:0]  color_dout,
    output wire [11:0] char_addr,
    input  wire [7:0]  char_dout,
    output reg  [7:0]  r_q,
    output reg  [7:0]  g_q,
    output reg  [7:0]  b_q,
    output reg         de_q,
    output reg         hsync_q,
    output reg         vsync_q
);

    function [23:0] palette(input [3:0] color);
        case (color)
            4'd0:  palette = 24'h000000;    // Schwarz
            4'd1:  palette = 24'hFFFFFF;    // Weiß
            4'd2:  palette = 24'h68372B;    // Rot
            4'd3:  palette = 24'h70A4B2;    // Cyan
            4'd4:  palette = 24'h6F3D86;    // Violett
            4'd5:  palette = 24'h588D43;    // Grün
            4'd6:  palette = 24'h352879;    // Blau
            4'd7:  palette = 24'hB8C76F;    // Gelb
            4'd8:  palette = 24'h6F4F25;    // Orange
            4'd9:  palette = 24'h433900;    // Braun
            4'd10: palette = 24'h9A6759;    // Hellrot
            4'd11: palette = 24'h444444;    // Dunkelgrau
            4'd12: palette = 24'h6C6C6C;    // Grau
            4'd13: palette = 24'h9AD284;    // Hellgrün
            4'd14: palette = 24'h6C5EB5;    // Hellblau
            4'd15: palette = 24'h959595;    // Hellgrau
        endcase
    endfunction

    // --- Station 1: Zelle bestimmen -----------------------------------------
    // Ein Zeichen ist 16x16 Bildpunkte groß (8x8 verdoppelt).
    localparam [11:0] V_START = V_OFFSET;   // auf die Breite von y gebracht

    wire [11:0] text_y  = y - V_START;
    wire        in_text = de && (y >= V_OFFSET) && (y < V_OFFSET + 400);
    wire [5:0]  col     = x[9:4];           // 0..39
    wire [4:0]  row     = text_y[8:4];      // 0..24
    wire [9:0]  cell_no = {row, 5'b0} + {2'b0, row, 3'b0} + {4'b0, col};  // row*40 + col

    assign ram_addr   = SCREEN_BASE + {6'b0, cell_no};
    assign color_addr = cell_no;

    reg [2:0] line_d1_q;        // Pixelzeile im Zeichen, 0..7
    reg [2:0] px_d1_q;          // Pixelspalte im Zeichen, 0..7
    reg       in_text_d1_q;
    reg [2:0] sync_d1_q;        // {de, hsync, vsync}

    // --- Station 2: Adresse im Char-ROM -------------------------------------
    // Die Zeichenfarbe ist schon da; sie wartet eine Station auf das Muster.
    assign char_addr = {1'b0, ram_dout, line_d1_q};

    reg [3:0] color_d2_q;
    reg [2:0] px_d2_q;
    reg       in_text_d2_q;
    reg [2:0] sync_d2_q;

    // --- Station 3: Pixel auswählen -----------------------------------------
    // Bit 7 des Musters ist das linke Pixel.
    wire        pixel = char_dout[3'd7 - px_d2_q];
    wire [23:0] rgb   = !sync_d2_q[2] ? 24'h000000 :
                        !in_text_d2_q ? palette(border_color) :
                        pixel         ? palette(color_d2_q)   : palette(bg_color);

    always @(posedge clk) begin
        if (en) begin
            line_d1_q    <= text_y[3:1];
            px_d1_q      <= x[3:1];
            in_text_d1_q <= in_text;
            sync_d1_q    <= {de, hsync, vsync};

            color_d2_q   <= color_dout;
            px_d2_q      <= px_d1_q;
            in_text_d2_q <= in_text_d1_q;
            sync_d2_q    <= sync_d1_q;

            {r_q, g_q, b_q}           <= rgb;
            {de_q, hsync_q, vsync_q}  <= sync_d2_q;
        end
    end

endmodule

`default_nettype wire
