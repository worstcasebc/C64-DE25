// tb_c64_video — selbstprüfende Testbench für Rechner und Textmodus zusammen.
//
// soc_c64 + video_timing + video_text, verdrahtet wie im Top-Level. Das
// Testprogramm (sw/asm/banktest.s) füllt den Bildschirmspeicher; danach wird
// ein vollständiges Bild aufgezeichnet und geprüft:
// 1. Rahmenfarbe über und unter dem Textbereich.
// 2. Alle 256 Zeichen ab Zeile 2: Im Test-Char-ROM ist das Muster jedes
//    Zeichens sein eigener Code, also lässt sich jedes Pixel nachrechnen —
//    richtige Zelle, richtige Pixelzeile, richtiges Bit, doppelte Größe.
// 3. Titel in Zeile 0 und Leerzeichen in der letzten Zelle.
// Das Bild wird außerdem als tb/build/tb_c64_video.ppm gespeichert.
//
// Mit Plusargs lässt sich dieselbe Testbench für Bildschirmfotos anderer
// ROMs nutzen (siehe tb/screenshot.py):
//   +basic=<hex> +char=<hex> +kernal=<hex>   ROM-Inhalte ersetzen
//   +wait=<Takte>                            Wartezeit vor der Aufnahme
//   +nocheck                                 Prüfungen 1-3 überspringen

`timescale 1ns / 1ps
`default_nettype none

module tb_c64_video;

    localparam [23:0] BORDER = 24'h6C5EB5, BG = 24'h352879, FG = 24'h6C5EB5;
    localparam        W = 640, H = 480;

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    reg  pix_en = 1'b0;

    wire [11:0] x;
    wire [11:0] y;
    wire        de;
    wire        hsync;
    wire        vsync;
    wire [15:0] vid_ram_addr;
    wire [7:0]  vid_ram_dout;
    wire [11:0] vid_char_addr;
    wire [7:0]  vid_char_dout;
    wire [7:0]  r;
    wire [7:0]  g;
    wire [7:0]  b;
    wire        de_out;
    wire        hsync_out;
    wire        vsync_out;
    wire        uart_txd;

    integer errors = 0;

    soc_c64 #(.CPU_DIV(1), .UART_CLKS_PER_BIT(4)) dut (
        .clk           (clk),
        .rst           (rst),
        .uart_txd      (uart_txd),
        .vid_en        (pix_en),
        .vid_ram_addr  (vid_ram_addr),
        .vid_ram_dout  (vid_ram_dout),
        .vid_char_addr (vid_char_addr),
        .vid_char_dout (vid_char_dout)
    );

    video_timing u_timing (
        .clk   (clk),
        .rst   (rst),
        .en    (pix_en),
        .x_q   (x),
        .y_q   (y),
        .de    (de),
        .hsync (hsync),
        .vsync (vsync)
    );

    video_text u_text (
        .clk       (clk),
        .en        (pix_en),
        .x         (x),
        .y         (y),
        .de        (de),
        .hsync     (hsync),
        .vsync     (vsync),
        .ram_addr  (vid_ram_addr),
        .ram_dout  (vid_ram_dout),
        .char_addr (vid_char_addr),
        .char_dout (vid_char_dout),
        .r_q       (r),
        .g_q       (g),
        .b_q       (b),
        .de_q      (de_out),
        .hsync_q   (hsync_out),
        .vsync_q   (vsync_out)
    );

    always #10 clk = ~clk;
    always @(posedge clk) pix_en <= rst ? 1'b0 : ~pix_en;

    // --- Bild aufzeichnen ---------------------------------------------------
    reg [23:0] frame [0:W*H-1];
    integer    n_pixels   = 0;
    reg        capturing  = 1'b0;
    reg        vsync_prev = 1'b0;
    reg        armed      = 1'b0;   // 1: beim nächsten vsync beginnt die Aufnahme

    always @(negedge clk) begin
        if (!pix_en) begin              // direkt nach einem Pixeltakt
            if (armed && vsync_out && !vsync_prev) begin
                capturing = 1'b1;
                armed     = 1'b0;
            end
            if (capturing && de_out && n_pixels < W * H) begin
                frame[n_pixels] = {r, g, b};
                n_pixels = n_pixels + 1;
            end
            vsync_prev = vsync_out;
        end
    end

    // --- Prüfhilfen ---------------------------------------------------------
    task expect_pixel(input integer px, input integer py, input [23:0] want);
        begin
            if (frame[py * W + px] !== want) begin
                if (errors < 20)
                    $display("FAIL: Pixel (%0d,%0d) ist %h, erwartet %h", px, py, frame[py * W + px], want);
                errors = errors + 1;
            end
        end
    endtask

    // Prüft eine Pixelzeile eines Zeichens: 8 Pixel, jedes 2x2 Bildpunkte.
    task expect_cell_line(input integer col, input integer row, input integer line,
                          input [7:0] pattern);
        integer px, dx, dy;
        begin
            for (px = 0; px < 8; px = px + 1)
                for (dx = 0; dx < 2; dx = dx + 1)
                    for (dy = 0; dy < 2; dy = dy + 1)
                        expect_pixel(col * 16 + px * 2 + dx, 40 + row * 16 + line * 2 + dy,
                                     pattern[7 - px] ? FG : BG);
        end
    endtask

    task write_ppm;
        integer fd, i;
        begin
            fd = $fopen("tb/build/tb_c64_video.ppm", "w");
            $fwrite(fd, "P3\n%0d %0d\n255\n", W, H);
            for (i = 0; i < W * H; i = i + 1)
                $fwrite(fd, "%0d %0d %0d\n", frame[i][23:16], frame[i][15:8], frame[i][7:0]);
            $fclose(fd);
        end
    endtask

    // --- Ablauf -------------------------------------------------------------
    reg [8*256-1:0] rom_file;
    integer         wait_clks;
    integer         code, line, pos;

    initial begin
        if (!$value$plusargs("wait=%d", wait_clks)) wait_clks = 100_000;

        // ROM-Inhalte ersetzen (nach dem $readmemh der ROM-Module selbst)
        #1;
        if ($value$plusargs("basic=%s",  rom_file)) $readmemh(rom_file, dut.u_rom_basic.mem);
        if ($value$plusargs("char=%s",   rom_file)) $readmemh(rom_file, dut.u_rom_char.mem);
        if ($value$plusargs("kernal=%s", rom_file)) $readmemh(rom_file, dut.u_rom_kernal.mem);

        repeat (5) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // Programm laufen lassen, dann ein ganzes Bild aufnehmen
        repeat (wait_clks) @(posedge clk);
        armed = 1'b1;
        wait (n_pixels == W * H);
        write_ppm;

        if (!$test$plusargs("nocheck")) begin
            // 1. Rahmen
            expect_pixel(0,   0,   BORDER);
            expect_pixel(639, 0,   BORDER);
            expect_pixel(320, 39,  BORDER);
            expect_pixel(320, 440, BORDER);
            expect_pixel(639, 479, BORDER);

            // 2. Zeichen 0..255 ab Zelle 80 (Zeile 2)
            for (code = 0; code < 256; code = code + 1) begin
                pos = 80 + code;
                for (line = 0; line < 8; line = line + 1)
                    expect_cell_line(pos % 40, pos / 40, line,
                                     (code == 0) ? ((line == 0) ? 8'h43 : 8'h00) : code[7:0]);
            end

            // 3. Titel "DE25-..." (D = 4, E = 5, 2 = $32) und Leerzeichen
            expect_cell_line(0,  0,  3, 8'h04);
            expect_cell_line(1,  0,  3, 8'h05);
            expect_cell_line(2,  0,  3, 8'h32);
            expect_cell_line(39, 24, 7, 8'h20);
        end

        if (errors == 0) $display("PASS: tb_c64_video");
        else             $display("FAIL: tb_c64_video (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
