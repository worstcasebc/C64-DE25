// video_upscaler — macht aus dem PAL-Bild des VIC-II ein Bild in einem
//                  Normformat für HDMI (Default: 720p50), über einen
//                  Bildspeicher.
//
// Zweck:  Ein Fernseher nimmt nur Bilder aus einer festen Liste von Formaten
//         an. Das Raster des VIC-II (504 Punkte, 312 Zeilen, 50,08 Hz) passt
//         in keines davon. Deshalb wird das Bild vom Takt des C64 gelöst:
//         Der VIC-II schreibt in einen Speicher, ein eigener Bildgenerator
//         liest ihn im Normraster aus — wie ein Kopierer, der die Vorlage in
//         seinem eigenen Tempo abtastet. Jeder Punkt des C64 wird dabei
//         SCALE x SCALE Bildpunkte groß (Default 3 x 3); gezeigt wird ein
//         Fenster von SRC_W x SRC_H Punkten aus dem VIC-Bild, mittig im
//         sichtbaren Bild, der Rest ist schwarz.
// Zwei Bildspeicher:
//         Schreiber und Leser laufen verschieden schnell. Mit nur einem
//         Speicher überholte der Schreiber den Leser immer wieder mitten im
//         Bild; oben stünde dann das neue, unten das alte Bild. Deshalb zwei
//         Speicher, wie zwei Tafeln: Der Schreiber wechselt mit jedem Bild
//         die Tafel. Der Leser wählt zu Beginn jedes seiner Bilder:
//           - Hat der Schreiber auf seiner Tafel schon die ersten Zeilen
//             geschrieben, liest der Leser dieselbe Tafel — er läuft hinter
//             dem Schreiber her und holt ihn nicht ein.
//           - Sonst liest er die andere Tafel mit dem fertigen Bild; die
//             wird erst ein ganzes Bild später wieder beschrieben.
//         Weil der C64 etwas mehr Bilder pro Sekunde liefert als die Norm,
//         wird ab und zu eines ausgelassen (bei 720p50 etwa alle 12 s).
//         Voraussetzungen: Der Schreiber braucht für eine Zeile nicht länger
//         als der Leser für SCALE Zeilen, und der Leser ist mit seinem Bild
//         fertig, bevor der Schreiber dieselbe Tafel erneut erreicht (beides
//         erfüllt bei 720p50 und 1080p50; geprüft in tb_video_upscaler).
// Speicher: Eine Tafel hat SRC_W x SRC_H Punkte zu 4 Bit. Ein Block-RAM des
//         Agilex 5 ist bei dieser Tiefe 10 Bit breit; mit einem Punkt pro
//         Wort blieben 6 Bit ungenutzt. Deshalb stehen zwei benachbarte
//         Punkte in einem Wort (links in Bit 3..0) — SRC_W muss gerade sein.
//         720p50: 2 x 22 Block-RAMs.
// Takte:  Zwei Domänen.
//           clk      Takt des C64 (31,5 MHz); pix_en = 1 in jedem vierten Takt
//           clk_vid  Pixeltakt des Normformats (720p50: 74,25 MHz)
//         Die Bildspeicher (ram_2clk) sind der Übergang. Dazu kommt der
//         Stand des Schreibers (welche Tafel, schon begonnen) als zwei Bits
//         durch einen sync_2ff; sie sind so kodiert, dass sich immer nur
//         eines ändert (Gray-Code), ein Zwischenwert also nie falsch ist.
// Ports:  pix_en, color, hblank, vblank — vom VIC-II (soc_c64). Gezählt wird
//         wie in video_scandoubler: Pixel ab Beginn der Zeilenlücke (hblank
//         steigt), Zeile ab der ersten Zeile nach Beginn der Bildlücke
//         (vblank steigt). X_FIRST (mindestens 1) und Y_FIRST sind die linke
//         obere Ecke des Fensters.
//         r_q/g_q/b_q, de_q, hsync_q, vsync_q — Bild im Takt clk_vid;
//         hsync/vsync sind 1 während des Impulses.
// Formate (CEA-861), Sync-Impulse am Stecker jeweils high-aktiv:
//           720p50   74,25 MHz  1280 + 440 + 40 + 220, 720 + 5 + 5 + 20
//                    SCALE 3, Fenster 360 x 240, Y_FIRST 42
//           1080p50  148,5 MHz  1920 + 528 + 44 + 148, 1080 + 4 + 5 + 36
//                    SCALE 4, Fenster 360 x 270, Y_FIRST 27

`default_nettype none

module video_upscaler #(
    // Das Textfenster des VIC-II (320 x 200) beginnt bei Pixel 140, Zeile 62
    // (gemessen in tb_c64_video). Mit diesen Werten liegt es in der Mitte:
    // 20 Pixel Rahmen links und rechts, 20 Zeilen oben und unten.
    parameter X_FIRST  = 120,
    parameter Y_FIRST  = 42,
    parameter SRC_W    = 360,
    parameter SRC_H    = 240,
    parameter SCALE    = 3,     // 1..8
    parameter H_ACTIVE = 1280,
    parameter H_FP     = 440,
    parameter H_SYNC   = 40,
    parameter H_BP     = 220,
    parameter V_ACTIVE = 720,
    parameter V_FP     = 5,
    parameter V_SYNC   = 5,
    parameter V_BP     = 20
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       pix_en,
    input  wire [3:0] color,
    input  wire       hblank,
    input  wire       vblank,

    input  wire       clk_vid,
    input  wire       rst_vid,
    output reg  [7:0] r_q,
    output reg  [7:0] g_q,
    output reg  [7:0] b_q,
    output reg        de_q,
    output reg        hsync_q,
    output reg        vsync_q
);

    localparam WORDS      = (SRC_W / 2) * SRC_H;    // zwei Punkte pro Wort
    localparam ADDR_W     = $clog2(WORDS);
    localparam START_ROWS = 2;      // so viele Zeilen Vorsprung braucht der Schreiber

    localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;
    localparam PIC_W   = SRC_W * SCALE;
    localparam PIC_H   = SRC_H * SCALE;
    localparam X_OFF   = (H_ACTIVE - PIC_W) / 2;
    localparam Y_OFF   = (V_ACTIVE - PIC_H) / 2;
    // Zeile, an deren Ende der Leser seine Tafel wählt: die letzte vor dem Bild
    localparam CHOOSE_Y = (Y_OFF == 0) ? V_TOTAL - 1 : Y_OFF - 1;
    localparam [ADDR_W-1:0] ROW_STEP = SRC_W / 2;

    // --- Schreiber (clk): Position im VIC-Bild ------------------------------
    reg              hblank_q;
    reg              vblank_q;
    reg [8:0]        dot_q;             // Pixel in der Zeile, 0 = erstes der Zeilenlücke
    reg [8:0]        line_q;            // Zeile im Bild
    reg              frame_start_q;     // die nächste Zeile ist Zeile 0
    reg [ADDR_W-1:0] wr_addr_q;         // nächstes freies Wort der Tafel
    reg              half_q;            // der linke Punkt eines Paars wartet
    reg [3:0]        left_q;            // seine Farbe

    // Stand des Schreibers, Gray-kodiert: Bit 1 = Tafel, auf die er schreibt;
    // Bit 1 ungleich Bit 0 = die ersten Zeilen stehen schon darauf.
    //   00 Tafel 0, noch nicht begonnen   01 Tafel 0, begonnen
    //   11 Tafel 1, noch nicht begonnen   10 Tafel 1, begonnen
    reg [1:0]        wr_state_q;

    wire       line_start = pix_en && hblank && !hblank_q;
    wire [8:0] dot_now    = line_start ? 9'd0 : dot_q + 1'b1;
    wire [8:0] line_now   = !line_start   ? line_q :
                            frame_start_q ? 9'd0   : line_q + 1'b1;

    wire store = pix_en && dot_now  >= X_FIRST && dot_now  < X_FIRST + SRC_W
                        && line_now >= Y_FIRST && line_now < Y_FIRST + SRC_H;

    always @(posedge clk) begin
        if (rst) begin
            hblank_q      <= 1'b0;
            vblank_q      <= 1'b0;
            dot_q         <= 9'd0;
            line_q        <= 9'd0;
            frame_start_q <= 1'b0;
            wr_addr_q     <= {ADDR_W{1'b0}};
            half_q        <= 1'b0;
            wr_state_q    <= 2'b00;
        end else if (pix_en) begin
            hblank_q <= hblank;
            vblank_q <= vblank;
            dot_q    <= dot_now;
            line_q   <= line_now;
            if (store) begin
                // Der linke Punkt wartet, mit dem rechten wird geschrieben.
                half_q <= ~half_q;
                if (half_q) wr_addr_q <= wr_addr_q + 1'b1;
                else        left_q    <= color;
            end

            if (line_start) begin
                frame_start_q <= vblank && !vblank_q;
                if (frame_start_q) begin
                    // Neues Bild: Tafel wechseln, von vorn beginnen.
                    wr_addr_q  <= {ADDR_W{1'b0}};
                    half_q     <= 1'b0;
                    wr_state_q <= {~wr_state_q[1], ~wr_state_q[1]};
                end else if (line_now == Y_FIRST + START_ROWS) begin
                    wr_state_q <= {wr_state_q[1], ~wr_state_q[1]};
                end
            end else if (vblank && !vblank_q) begin
                frame_start_q <= 1'b1;
            end
        end
    end

    // --- Leser (clk_vid): Normraster ----------------------------------------
    wire [11:0] x;
    wire [11:0] y;
    wire        de;
    wire        hsync;
    wire        vsync;

    video_timing #(
        .H_ACTIVE (H_ACTIVE), .H_FP (H_FP), .H_SYNC (H_SYNC), .H_BP (H_BP),
        .V_ACTIVE (V_ACTIVE), .V_FP (V_FP), .V_SYNC (V_SYNC), .V_BP (V_BP)
    ) u_timing (
        .clk   (clk_vid),
        .rst   (rst_vid),
        .en    (1'b1),
        .x_q   (x),
        .y_q   (y),
        .de    (de),
        .hsync (hsync),
        .vsync (vsync)
    );

    wire [1:0] state_vid_q;

    sync_2ff #(.WIDTH(2)) u_sync_state (
        .clk      (clk_vid),
        .d_async  (wr_state_q),
        .d_sync_q (state_vid_q)
    );

    wire wr_buf_vid  = state_vid_q[1];
    wire started_vid = state_vid_q[1] ^ state_vid_q[0];

    wire in_y   = (y >= Y_OFF) && (y < Y_OFF + PIC_H);
    wire in_pic = in_y && (x >= X_OFF) && (x < X_OFF + PIC_W);

    reg              rd_buf_q;      // Tafel, die in diesem Bild gelesen wird
    reg [8:0]        col_q;         // Punkt des C64 in der Zeile
    reg [2:0]        sub_x_q;       // wievielter Bildpunkt dieses Punkts
    reg [2:0]        sub_y_q;       // wievielte Bildzeile dieser Zeile
    reg [ADDR_W-1:0] row_base_q;    // Wort mit dem ersten Punkt der Zeile

    always @(posedge clk_vid) begin
        if (rst_vid) begin
            rd_buf_q   <= 1'b0;
            col_q      <= 9'd0;
            sub_x_q    <= 3'd0;
            sub_y_q    <= 3'd0;
            row_base_q <= {ADDR_W{1'b0}};
        end else begin
            if (in_pic) begin
                if (sub_x_q == SCALE - 1) begin
                    sub_x_q <= 3'd0;
                    col_q   <= col_q + 1'b1;
                end else begin
                    sub_x_q <= sub_x_q + 1'b1;
                end
            end

            if (x == H_ACTIVE) begin        // Zeilenende
                col_q   <= 9'd0;
                sub_x_q <= 3'd0;
                if (!in_y) begin
                    sub_y_q    <= 3'd0;
                    row_base_q <= {ADDR_W{1'b0}};
                end else if (sub_y_q == SCALE - 1) begin
                    sub_y_q    <= 3'd0;
                    row_base_q <= row_base_q + ROW_STEP;
                end else begin
                    sub_y_q <= sub_y_q + 1'b1;
                end
                if (y == CHOOSE_Y) rd_buf_q <= started_vid ? wr_buf_vid : ~wr_buf_vid;
            end
        end
    end

    // --- Die beiden Tafeln --------------------------------------------------
    wire [ADDR_W-1:0] rd_addr = row_base_q + col_q[8:1];
    wire [7:0]        pair_0;
    wire [7:0]        pair_1;

    ram_2clk #(.ADDR_W(ADDR_W), .DATA_W(8), .DEPTH(WORDS)) u_frame_0 (
        .wr_clk    (clk),
        .wr_en     (store && half_q && !wr_state_q[1]),
        .wr_addr   (wr_addr_q),
        .wr_din    ({color, left_q}),
        .rd_clk    (clk_vid),
        .rd_addr   (rd_addr),
        .rd_dout_q (pair_0)
    );

    ram_2clk #(.ADDR_W(ADDR_W), .DATA_W(8), .DEPTH(WORDS)) u_frame_1 (
        .wr_clk    (clk),
        .wr_en     (store && half_q && wr_state_q[1]),
        .wr_addr   (wr_addr_q),
        .wr_din    ({color, left_q}),
        .rd_clk    (clk_vid),
        .rd_addr   (rd_addr),
        .rd_dout_q (pair_1)
    );

    // Stufe 1: Das Wort kommt einen Takt nach der Adresse; welcher der
    // beiden Punkte gemeint ist, Fenster und Steuersignale laufen mit.
    reg right_1_q;
    reg in_pic_1_q;
    reg de_1_q;
    reg hsync_1_q;
    reg vsync_1_q;

    wire [7:0]  pair = rd_buf_q ? pair_1 : pair_0;
    wire [23:0] rgb;

    c64_palette u_palette (
        .color (right_1_q ? pair[7:4] : pair[3:0]),
        .rgb   (rgb)
    );

    always @(posedge clk_vid) begin
        right_1_q  <= col_q[0];
        in_pic_1_q <= in_pic;
        de_1_q     <= de;
        hsync_1_q  <= hsync;
        vsync_1_q  <= vsync;

        // Stufe 2: Farbnummer in RGB übersetzen.
        {r_q, g_q, b_q} <= in_pic_1_q ? rgb : 24'h000000;
        de_q            <= de_1_q;
        hsync_q         <= hsync_1_q;
        vsync_q         <= vsync_1_q;
    end

endmodule

`default_nettype wire
