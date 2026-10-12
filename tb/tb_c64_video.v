// tb_c64_video — selbstprüfende Testbench für das Bild des C64-Rechners.
// Simulator: Questa
//
// soc_c64 mit dem echten VIC-II, dazu Lader, Warteschlange und Tipp-Modul wie
// im Top-Level. Das Testprogramm (sw/asm/banktest.s) füllt den
// Bildschirmspeicher; danach wird ein vollständiges VIC-Bild aufgezeichnet
// (504 x 312 Pixel einschließlich der Lücken) und geprüft:
// 1. Rahmenfarbe rund um das Textfenster.
// 2. Alle 256 Zeichen ab Zeile 2: Im Test-Char-ROM ist das Muster jedes
//    Zeichens sein eigener Code, also lässt sich jedes Pixel nachrechnen —
//    richtige Zelle, richtige Pixelzeile, richtiges Bit.
// 3. Titel in Zeile 0 (weiß, also über das Farb-RAM anders gefärbt) und
//    Leerzeichen in der letzten Zelle.
// Das Bild wird außerdem als tb/build/tb_c64_video.ppm gespeichert.
//
// Gezählt wird wie in video_scandoubler: Pixel ab Beginn der Zeilenlücke,
// Zeilen ab der ersten Zeile nach Beginn der Bildlücke. Das Textfenster
// (320 x 200) beginnt dann bei WIN_X/WIN_Y.
//
// Der Rechner läuft mit PIX_DIV = 1 (8 Systemtakte pro CPU-Takt).
//
// Mit Plusargs lässt sich dieselbe Testbench für Bildschirmfotos anderer
// ROMs nutzen (siehe tb/screenshot.py):
//   +basic=<hex> +char=<hex> +kernal=<hex>   ROM-Inhalte ersetzen
//   +wait=<Takte>                            Wartezeit vor der Aufnahme
//   +load=<hex> +loadlen=<n>                 danach n Bytes aus der Datei so
//                                            einspielen, als kämen sie vom
//                                            UART (Ladeblöcke für prg_loader)
//   +type=<Text>                             danach Text und Enter auf
//                                            einmal in die Warteschlange
//                                            legen und tippen lassen, dann
//                                            +after=<Takte> warten.
//                                            Im Text steht | für Enter und
//                                            ~ für Esc (RUN/STOP).
//   +nocheck                                 Prüfungen 1-3 überspringen

`timescale 1ns / 1ps
`default_nettype none

module tb_c64_video;

    localparam W = 504, H = 312;        // ganzes VIC-Bild mit Lücken
    localparam WIN_X = 140, WIN_Y = 62; // linke obere Ecke des Textfensters
    localparam [3:0] BORDER = 4'd14, BG = 4'd6, FG = 4'd14, WHITE = 4'd1;

    reg  clk = 1'b0;
    reg  rst = 1'b1;

    wire        uart_txd;
    wire [63:0] keys;
    wire        typer_busy;
    wire        fifo_empty;
    wire        fifo_full;
    wire [7:0]  fifo_data;
    wire        fifo_rd;
    wire [7:0]  key_data;
    wire        key_valid;
    wire        dma_req;
    wire [15:0] dma_addr;
    wire [7:0]  dma_data;
    wire        dma_ack;
    wire        loader_active;
    reg  [7:0]  type_data  = 8'h00;
    reg         type_valid = 1'b0;
    wire        pix_en;
    wire [3:0]  vic_color;
    wire        vic_hblank;
    wire        vic_vblank;

    integer errors = 0;

    soc_c64 #(.PIX_DIV(1), .UART_CLKS_PER_BIT(4)) dut (
        .clk        (clk),
        .rst        (rst),
        .uart_txd   (uart_txd),
        .keys       (keys),
        .joy1       (5'd0),
        .joy2       (5'd0),
        .restore    (1'b0),
        .iec_atn_o  (),
        .iec_clk_o  (),
        .iec_data_o (),
        .iec_clk_i  (1'b1),
        .iec_data_i (1'b1),
        .dma_req    (dma_req),
        .dma_addr   (dma_addr),
        .dma_data   (dma_data),
        .dma_ack    (dma_ack),
        .pix_en     (pix_en),
        .vic_color  (vic_color),
        .vic_hblank (vic_hblank),
        .vic_vblank (vic_vblank),
        .sid_audio  (),
        .cpu_tick   ()
    );

    // type_data/type_valid spielen den UART-Empfänger.
    prg_loader #(.TIMEOUT_CLKS(8_000_000)) u_loader (
        .clk       (clk),
        .rst       (rst),
        .rx_data   (type_data),
        .rx_valid  (type_valid),
        .key_data  (key_data),
        .key_valid (key_valid),
        .dma_req   (dma_req),
        .dma_addr  (dma_addr),
        .dma_data  (dma_data),
        .dma_ack   (dma_ack),
        .active    (loader_active)
    );

    fifo_sync #(.ADDR_W(8)) u_key_fifo (
        .clk    (clk),
        .rst    (rst),
        .wr_en  (key_valid),
        .din    (key_data),
        .full   (fifo_full),
        .rd_en  (fifo_rd),
        .dout_q (fifo_data),
        .empty  (fifo_empty)
    );

    // Tastendauer passend zur Simulation: Das KERNAL fragt die Tastatur etwa
    // alle 17000 CPU-Takte ab, hier also alle 136000 Systemtakte.
    ascii_key_typer #(.PRESS_CLKS(320_000), .RELEASE_CLKS(320_000)) u_typer (
        .clk        (clk),
        .rst        (rst),
        .fifo_empty (fifo_empty),
        .fifo_data  (fifo_data),
        .fifo_rd    (fifo_rd),
        .busy       (typer_busy),
        .keys       (keys)
    );

    always #10 clk = ~clk;

    // --- Bild aufzeichnen ---------------------------------------------------
    reg [3:0] frame [0:W*H-1];
    reg       hblank_prev  = 1'b0;
    reg       vblank_prev  = 1'b0;
    reg       frame_start  = 1'b0;  // die nächste Zeile ist Zeile 0
    reg       armed        = 1'b0;  // 1: beim nächsten Bildanfang beginnt die Aufnahme
    reg       capturing    = 1'b0;
    reg       captured     = 1'b0;
    integer   dot          = 0;
    integer   line         = 0;

    always @(posedge clk) begin
        if (pix_en) begin
            if (vic_vblank && !vblank_prev) frame_start = 1'b1;
            if (vic_hblank && !hblank_prev) begin
                dot = 0;
                if (frame_start) begin
                    if (capturing) begin
                        capturing = 1'b0;
                        captured  = 1'b1;
                    end else if (armed) begin
                        capturing = 1'b1;
                        armed     = 1'b0;
                    end
                    line        = 0;
                    frame_start = 1'b0;
                end else begin
                    line = line + 1;
                end
            end else begin
                dot = dot + 1;
            end
            if (capturing && dot < W && line < H) frame[line * W + dot] = vic_color;
            hblank_prev = vic_hblank;
            vblank_prev = vic_vblank;
        end
    end

    // --- Prüfhilfen ---------------------------------------------------------
    task expect_pixel(input integer px, input integer py, input [3:0] want);
        begin
            if (frame[py * W + px] !== want) begin
                if (errors < 20)
                    $display("FAIL: Pixel (%0d,%0d) hat Farbe %0d, erwartet %0d", px, py, frame[py * W + px], want);
                errors = errors + 1;
            end
        end
    endtask

    // Prüft eine Pixelzeile eines Zeichens im Textfenster.
    task expect_cell_line(input integer col, input integer row, input integer char_line,
                          input [7:0] pattern, input [3:0] fg);
        integer px;
        begin
            for (px = 0; px < 8; px = px + 1)
                expect_pixel(WIN_X + col * 8 + px, WIN_Y + row * 8 + char_line,
                             pattern[7 - px] ? fg : BG);
        end
    endtask

    // Farbnummer -> RGB über dieselbe Tabelle wie auf dem Board.
    reg  [3:0]  pal_index = 4'd0;
    wire [23:0] pal_rgb;

    c64_palette u_palette (
        .color (pal_index),
        .rgb   (pal_rgb)
    );

    task write_ppm;
        integer fd, i;
        begin
            fd = $fopen("tb/build/tb_c64_video.ppm", "w");
            $fwrite(fd, "P3\n%0d %0d\n255\n", W, H);
            for (i = 0; i < W * H; i = i + 1) begin
                pal_index = frame[i];
                #1;
                $fwrite(fd, "%0d %0d %0d\n", pal_rgb[23:16], pal_rgb[15:8], pal_rgb[7:0]);
            end
            $fclose(fd);
        end
    endtask

    // --- Ablauf -------------------------------------------------------------
    reg [8*256-1:0] rom_file;
    reg [8*128-1:0] type_text;
    integer         wait_clks;
    integer         after_clks;
    integer         code, char_line, pos, n;

    task type_char(input [7:0] ch);     // ein Byte "vom UART", danach kurze Pause
        begin
            @(negedge clk);
            type_data = ch; type_valid = 1'b1;
            @(negedge clk);
            type_valid = 1'b0;
            repeat (30) @(negedge clk);
        end
    endtask

    reg [7:0] load_bytes [0:65535];
    integer   load_len;

    initial begin
        if (!$value$plusargs("wait=%d", wait_clks)) wait_clks = 800_000;

        // ROM-Inhalte ersetzen (nach dem $readmemh der ROM-Module selbst)
        #1;
        if ($value$plusargs("basic=%s",  rom_file)) $readmemh(rom_file, dut.u_rom_basic.mem);
        if ($value$plusargs("char=%s",   rom_file)) $readmemh(rom_file, dut.u_rom_char.mem);
        if ($value$plusargs("kernal=%s", rom_file)) $readmemh(rom_file, dut.u_rom_kernal.mem);

        repeat (20) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // Programm laufen lassen
        repeat (wait_clks) @(posedge clk);

        // Auf Wunsch Ladeblöcke einspielen
        if ($value$plusargs("load=%s", rom_file)) begin
            if (!$value$plusargs("loadlen=%d", load_len)) load_len = 0;
            $readmemh(rom_file, load_bytes);
            for (n = 0; n < load_len; n = n + 1) type_char(load_bytes[n]);
        end

        // Auf Wunsch tippen: Text steht rechtsbündig in type_text, davor Nullen
        if ($value$plusargs("type=%s", type_text)) begin
            if (!$value$plusargs("after=%d", after_clks)) after_clks = 3_200_000;
            for (n = 127; n >= 0; n = n - 1)
                if (type_text[8*n +: 8] != 8'h00)
                    type_char(type_text[8*n +: 8] == "|" ? 8'h0D :
                              type_text[8*n +: 8] == "~" ? 8'h1B : type_text[8*n +: 8]);
            type_char(8'h0D);
            @(negedge clk);
            wait (!typer_busy);
            repeat (after_clks) @(posedge clk);
        end

        // Ein ganzes Bild aufnehmen
        armed = 1'b1;
        wait (captured);
        write_ppm;

        if (!$test$plusargs("nocheck")) begin
            // 1. Rahmen links, rechts, über und unter dem Textfenster
            expect_pixel(WIN_X - 1,   WIN_Y + 100, BORDER);
            expect_pixel(WIN_X + 320, WIN_Y + 100, BORDER);
            expect_pixel(WIN_X + 160, WIN_Y - 1,   BORDER);
            expect_pixel(WIN_X + 160, WIN_Y + 200, BORDER);

            // 2. Zeichen 0..255 ab Zelle 80 (Zeile 2)
            for (code = 0; code < 256; code = code + 1) begin
                pos = 80 + code;
                for (char_line = 0; char_line < 8; char_line = char_line + 1)
                    expect_cell_line(pos % 40, pos / 40, char_line,
                                     (code == 0) ? ((char_line == 0) ? 8'h43 : 8'h00) : code[7:0], FG);
            end

            // 3. Titel "DE25-..." (D = 4, E = 5, 2 = $32) und Leerzeichen
            expect_cell_line(0,  0,  3, 8'h04, WHITE);
            expect_cell_line(1,  0,  3, 8'h05, WHITE);
            expect_cell_line(2,  0,  3, 8'h32, WHITE);
            expect_cell_line(39, 24, 7, 8'h20, FG);
        end

        if (errors == 0) $display("PASS: tb_c64_video");
        else             $display("FAIL: tb_c64_video (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
