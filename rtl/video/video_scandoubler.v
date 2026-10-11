// video_scandoubler — Zeilenverdoppler: macht aus dem PAL-Bild des VIC-II ein
//                     Bild für HDMI.
//
// Zweck:  Der VIC-II liefert 312 Zeilen zu 504 Pixeln, 50-mal pro Sekunde —
//         halb so viele Zeilen pro Sekunde, wie ein HDMI-Monitor mindestens
//         annimmt. Deshalb wird jede Zeile zweimal ausgegeben, doppelt so
//         schnell: Eine Zeile wird in einen Zeilenspeicher geschrieben,
//         während die vorige zweimal hintereinander ausgelesen wird (wie
//         zwei Schreibblöcke, die abwechselnd beschrieben und vorgelesen
//         werden). Jedes Pixel wird auch doppelt so breit. Ergebnis:
//           1008 Pixel pro Zeile, 624 Zeilen, davon sichtbar 720 x 576
//         Sichtbar ist ein Fenster von 360 x 288 Pixeln aus dem VIC-Bild,
//         ab Pixel X_FIRST und Zeile Y_FIRST. Gezählt wird ab dem Beginn der
//         Zeilenlücke (hblank steigt) bzw. ab der ersten Zeile nach Beginn
//         der Bildlücke (vblank steigt).
// Takt:   clk muss das Vierfache des Pixeltakts sein: pix_en = 1 in jedem
//         vierten Takt. Ein Ausgangspixel dauert einen Takt.
// Ports:  pix_en, color, hblank, vblank — vom VIC-II (soc_c64).
//         r_q/g_q/b_q, de_q, hsync_q, vsync_q — Bild für HDMI; hsync/vsync
//         sind 1 während des Impulses.
// Rahmen: Rund um das sichtbare Fenster liegen die Lücken wie beim
//         erprobten Raster aus pal_test_top: waagerecht 72 + 96 (Sync) +
//         120, senkrecht 8 + 6 (Sync) + 34.

`default_nettype none

module video_scandoubler #(
    // Das Textfenster des VIC-II (320 x 200) beginnt bei Pixel 140, Zeile 62
    // (gemessen in tb_c64_video). Mit diesen Werten liegt es in der Mitte:
    // 20 Pixel Rahmen links und rechts, 44 Zeilen oben und unten.
    parameter X_FIRST = 120,    // erstes sichtbares Pixel der VIC-Zeile
    parameter Y_FIRST = 18      // erste sichtbare VIC-Zeile
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       pix_en,
    input  wire [3:0] color,
    input  wire       hblank,
    input  wire       vblank,
    output reg  [7:0] r_q,
    output reg  [7:0] g_q,
    output reg  [7:0] b_q,
    output reg        de_q,
    output reg        hsync_q,
    output reg        vsync_q
);

    localparam H_TOTAL = 1008, H_ACTIVE = 720, H_FP = 72, H_SYNC = 96;
    localparam V_TOTAL = 624,  V_ACTIVE = 576, V_FP = 8,  V_SYNC = 6;

    // --- Eingangsseite: Position im VIC-Bild --------------------------------
    reg       hblank_q;
    reg       vblank_q;
    reg [8:0] dot_q;            // Pixel in der Zeile, 0 = erstes der Zeilenlücke
    reg [8:0] line_q;           // Zeile im Bild
    reg       frame_start_q;    // die nächste Zeile ist Zeile 0
    reg       wr_sel_q;         // welcher der beiden Zeilenspeicher beschrieben wird

    wire       line_start = pix_en && hblank && !hblank_q;
    wire [8:0] dot_now    = line_start ? 9'd0 : dot_q + 1'b1;

    reg [3:0] line_mem [0:1023];    // zwei Zeilen zu je 512 Pixeln

    always @(posedge clk) begin
        if (pix_en) line_mem[{wr_sel_q ^ line_start, dot_now}] <= color;
    end

    // --- Ausgangsseite: Position im verdoppelten Bild -----------------------
    reg [9:0] out_x_q;          // 0..1007 innerhalb der Ausgangszeile
    reg       second_q;         // 0: erste, 1: zweite Ausgabe der Zeile
    reg [8:0] rd_line_q;        // Nummer der VIC-Zeile im Lesespeicher

    always @(posedge clk) begin
        if (rst) begin
            hblank_q      <= 1'b0;
            vblank_q      <= 1'b0;
            dot_q         <= 9'd0;
            line_q        <= 9'd0;
            frame_start_q <= 1'b0;
            wr_sel_q      <= 1'b0;
            out_x_q       <= 10'd0;
            second_q      <= 1'b0;
            rd_line_q     <= 9'd0;
        end else begin
            // Ausgangszähler läuft in jedem Takt.
            if (out_x_q == H_TOTAL - 1) begin
                out_x_q  <= 10'd0;
                second_q <= ~second_q;
            end else begin
                out_x_q <= out_x_q + 1'b1;
            end

            if (pix_en) begin
                hblank_q <= hblank;
                vblank_q <= vblank;
                dot_q    <= dot_now;
                if (vblank && !vblank_q) frame_start_q <= 1'b1;

                if (line_start) begin
                    // Zeilenwechsel: Speicher tauschen, Ausgabe neu ausrichten.
                    wr_sel_q      <= ~wr_sel_q;
                    rd_line_q     <= line_q;
                    line_q        <= frame_start_q ? 9'd0 : line_q + 1'b1;
                    frame_start_q <= 1'b0;
                    out_x_q       <= 10'd0;
                    second_q      <= 1'b0;
                end
            end
        end
    end

    // Stufe 1: Zeilenspeicher lesen, Position und Fenster mitführen.
    wire [9:0] out_line = {rd_line_q, second_q};        // 0..623

    // Position relativ zum Beginn des sichtbaren Fensters, im Kreis gezählt.
    localparam [10:0] H_START = 2 * X_FIRST,            // Fensterbeginn in Ausgangspunkten
                      V_START = 2 * Y_FIRST,
                      H_WRAP  = H_TOTAL - 2 * X_FIRST,  // Abstand vom Zeilenanfang im Kreis
                      V_WRAP  = V_TOTAL - 2 * Y_FIRST;

    wire [10:0] out_x11    = {1'b0, out_x_q};
    wire [10:0] out_line11 = {1'b0, out_line};

    wire [10:0] h_rel = (out_x11    >= H_START) ? out_x11    - H_START : out_x11    + H_WRAP;
    wire [10:0] v_rel = (out_line11 >= V_START) ? out_line11 - V_START : out_line11 + V_WRAP;

    reg [3:0] color_d1_q;
    reg       de_d1_q;
    reg       hsync_d1_q;
    reg       vsync_d1_q;

    wire [23:0] rgb;

    c64_palette u_palette (
        .color (color_d1_q),
        .rgb   (rgb)
    );

    always @(posedge clk) begin
        color_d1_q <= line_mem[{~wr_sel_q, out_x_q[9:1]}];
        de_d1_q    <= (h_rel < H_ACTIVE) && (v_rel < V_ACTIVE);
        hsync_d1_q <= (h_rel >= H_ACTIVE + H_FP) && (h_rel < H_ACTIVE + H_FP + H_SYNC);
        vsync_d1_q <= (v_rel >= V_ACTIVE + V_FP) && (v_rel < V_ACTIVE + V_FP + V_SYNC);

        // Stufe 2: Farbnummer in RGB übersetzen.
        {r_q, g_q, b_q} <= de_d1_q ? rgb : 24'h000000;
        de_q            <= de_d1_q;
        hsync_q         <= hsync_d1_q;
        vsync_q         <= vsync_d1_q;
    end

endmodule

`default_nettype wire
