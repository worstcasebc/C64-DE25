// video_osd — Textfenster, das über das fertige Bild gelegt wird (On-Screen
//             Display), beschrieben von Linux auf dem HPS.
//
// Zweck:  Ein Menü, das unabhängig vom C64 funktioniert — auch mitten in
//         einem Spiel. Das Modul sitzt hinter dem VIC-II im Bildweg, wie
//         eine Folie mit Text, die man vor den Bildschirm hält: Der C64
//         merkt nichts davon. Der Text steht in einem eigenen kleinen
//         Speicher (32 x 16 Zeichen), den Linux beschreibt; die Zeichen
//         kommen aus demselben Zeichensatz-ROM wie beim C64.
//         Im Fenster erscheinen gesetzte Pixel weiß, alle anderen zeigen
//         das Bild darunter auf ein Viertel abgedunkelt. Ein Zeichen ist
//         16 x 16 Bildpunkte groß (ein Zeichen des C64 misst in 720p50
//         24 x 24).
// Takte:  Zwei Domänen.
//           clk_av  Takt der Brücke (100 MHz): Schreiben in den Textspeicher
//           clk     Bildtakt (clk_vid, 74,25 MHz): alles Übrige
//         Der Textspeicher (ram_2clk) ist der Übergang; "sichtbar" kommt
//         durch einen sync_2ff. Kein Reset nötig außer für "sichtbar".
// Ports:  Seite HPS, nur Schreiben (avs_address zählt Worte):
//           0         Bit 0 = 1: Fenster sichtbar
//           512..1023 Textspeicher, ein Zeichen pro Wort (Bit 7..0), Zeile
//                     für Zeile. Der Wert ist der Bildschirmcode des C64
//                     (nicht ASCII); ab 128 erscheint das Zeichen invers.
//           avs_byteenable[0] muss gesetzt sein.
//         Bildseite: rgb, de, hsync, vsync herein; dasselbe drei Takte
//         später hinaus (rgb_q, de_q, hsync_q, vsync_q), mit oder ohne
//         Fenster. Die Lage im Bild wird aus de und vsync mitgezählt: X0, Y0
//         sind die linke obere Ecke des Fensters in Bildpunkten und Zeilen
//         des sichtbaren Bildes (Default: mittig in 720 x 576; das Top-Level
//         setzt sie für 1280 x 720).

`default_nettype none

module video_osd #(
    parameter CHAR_FILE = "sw/asm/build/banktest_char.hex",
    parameter X0        = 104,
    parameter Y0        = 160
) (
    input  wire        clk_av,
    input  wire        rst_av,
    input  wire [9:0]  avs_address,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire [3:0]  avs_byteenable,

    input  wire        clk,
    input  wire [23:0] rgb,
    input  wire        de,
    input  wire        hsync,
    input  wire        vsync,
    output reg  [23:0] rgb_q,
    output reg         de_q,
    output reg         hsync_q,
    output reg         vsync_q
);

    localparam WIN_W = 512;     // 32 Zeichen zu 16 Bildpunkten
    localparam WIN_H = 256;     // 16 Zeilen zu 16 Bildzeilen

    // --- Seite HPS (clk_av) -------------------------------------------------
    reg  visible_av_q;
    wire wr = avs_write && avs_byteenable[0];

    always @(posedge clk_av) begin
        if (rst_av)                         visible_av_q <= 1'b0;
        else if (wr && avs_address == 10'd0) visible_av_q <= avs_writedata[0];
    end

    wire visible_q;

    sync_2ff u_sync_visible (
        .clk      (clk),
        .d_async  (visible_av_q),
        .d_sync_q (visible_q)
    );

    // --- Lage im Bild mitzählen ---------------------------------------------
    // x_q ist die Nummer des Bildpunkts, der gerade am Eingang liegt; y_q die
    // Nummer der sichtbaren Zeile seit dem letzten vsync.
    reg [10:0] x_q = 11'd0;
    reg [10:0] y_q = 11'd0;
    reg        de_old_q = 1'b0;

    always @(posedge clk) begin
        de_old_q <= de;
        x_q      <= de ? x_q + 1'b1 : 11'd0;
        if (vsync)               y_q <= 11'd0;
        else if (de_old_q && !de) y_q <= y_q + 1'b1;
    end

    wire        in_win = de && x_q >= X0 && x_q < X0 + WIN_W && y_q >= Y0 && y_q < Y0 + WIN_H;
    wire [10:0] wx     = x_q - X0;      // Lage im Fenster
    wire [10:0] wy     = y_q - Y0;

    // --- Stufe 1: Zeichen aus dem Textspeicher ------------------------------
    wire [7:0] code;

    ram_2clk #(.ADDR_W(9), .DATA_W(8)) u_text (
        .wr_clk    (clk_av),
        .wr_en     (wr && avs_address[9]),
        .wr_addr   (avs_address[8:0]),
        .wr_din    (avs_writedata[7:0]),
        .rd_clk    (clk),
        .rd_addr   ({wy[7:4], wx[8:4]}),
        .rd_dout_q (code)
    );

    reg [23:0] rgb_1_q;
    reg        de_1_q, hsync_1_q, vsync_1_q, win_1_q;
    reg [2:0]  row_1_q, col_1_q;    // Zeile und Spalte im Zeichen (jede doppelt)

    always @(posedge clk) begin
        rgb_1_q   <= rgb;
        de_1_q    <= de;
        hsync_1_q <= hsync;
        vsync_1_q <= vsync;
        win_1_q   <= in_win;
        row_1_q   <= wy[3:1];
        col_1_q   <= wx[3:1];
    end

    // --- Stufe 2: Pixelzeile des Zeichens aus dem Zeichensatz ---------------
    // Erster Zeichensatz des C64 (Großbuchstaben und Grafik), 8 Bytes je
    // Zeichen.
    wire [7:0] glyph;

    rom_sync #(.ADDR_W(12), .INIT_FILE(CHAR_FILE)) u_font (
        .clk    (clk),
        .en     (1'b1),
        .addr   ({1'b0, code, row_1_q}),
        .dout_q (glyph)
    );

    reg [23:0] rgb_2_q;
    reg        de_2_q, hsync_2_q, vsync_2_q, win_2_q;
    reg [2:0]  col_2_q;

    always @(posedge clk) begin
        rgb_2_q   <= rgb_1_q;
        de_2_q    <= de_1_q;
        hsync_2_q <= hsync_1_q;
        vsync_2_q <= vsync_1_q;
        win_2_q   <= win_1_q;
        col_2_q   <= col_1_q;
    end

    // --- Stufe 3: mischen ---------------------------------------------------
    // Das linke Pixel eines Zeichens steht im obersten Bit.
    wire        pixel = glyph[3'd7 - col_2_q];
    wire [23:0] dimmed = {2'b00, rgb_2_q[23:18], 2'b00, rgb_2_q[15:10], 2'b00, rgb_2_q[7:2]};

    always @(posedge clk) begin
        if (visible_q && win_2_q) rgb_q <= pixel ? 24'hFFFFFF : dimmed;
        else                      rgb_q <= rgb_2_q;
        de_q    <= de_2_q;
        hsync_q <= hsync_2_q;
        vsync_q <= vsync_2_q;
    end

endmodule

`default_nettype wire
