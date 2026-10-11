// tb_video_scandoubler — selbstprüfende Testbench für video_scandoubler
//                        (und c64_palette).
//
// Die Testbench spielt den VIC-II: ein Raster mit 504 Pixeln und 312 Zeilen,
// ein Pixel alle 4 Takte, Zeilen- und Bildlücke wie beim Original. Die
// Farbnummer jedes Pixels wird aus seiner Position berechnet, sodass die
// Testbench für jeden Ausgangspunkt nachrechnen kann, was erscheinen muss.
// 1. Ausgangsraster: 1008 Takte pro Zeile, 624 Zeilen pro Bild, hsync 96
//    Takte, vsync 6 Zeilen.
// 2. Sichtbar sind genau 720 x 576 Punkte.
// 3. Jeder sichtbare Punkt zeigt das richtige VIC-Pixel (Fenster ab
//    X_FIRST/Y_FIRST, doppelt breit und doppelt hoch) in der richtigen
//    RGB-Farbe.
// 4. Außerhalb des sichtbaren Bereichs ist die Farbe Schwarz.
// Gemessen wird erst, nachdem sich der Verdoppler nach dem Reset auf das
// Bild ausgerichtet hat.

`timescale 1ns / 1ps
`default_nettype none

module tb_video_scandoubler;

    localparam X_FIRST = 118, Y_FIRST = 19;
    localparam W = 720, H = 576;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg  [1:0] sub = 2'd0;
    wire       pix_en = (sub == 2'd3);
    wire [7:0] r;
    wire [7:0] g;
    wire [7:0] b;
    wire       de;
    wire       hsync;
    wire       vsync;

    integer errors = 0;

    always #10 clk = ~clk;
    always @(posedge clk) sub <= sub + 2'd1;

    // --- Der gespielte VIC-II ------------------------------------------------
    // Eigene Zähler wie im Chip: x 0..503, y 0..311. Die Lücken liegen
    // irgendwo mitten im Zählbereich, wie beim Original.
    integer vx = 0, vy = 0;
    wire vic_hblank = (vx >= 396 && vx < 496);
    wire vic_vblank = (vy >= 300 || vy < 16);

    // Position so, wie video_scandoubler zählt: Pixel ab Beginn der
    // Zeilenlücke, Zeile ab der ersten Zeile nach Beginn der Bildlücke.
    wire [8:0] dot  = (vx >= 396) ? vx - 396 : vx + 504 - 396;
    // Die Zeile wechselt für den Verdoppler bei x = 396.
    wire [9:0] row_raw = (vx >= 396) ? vy + 1 : vy;
    wire [8:0] row  = (row_raw >= 301) ? row_raw - 301 : row_raw + 312 - 301;

    function [3:0] color_at(input [8:0] d, input [8:0] l);
        color_at = d[3:0] ^ l[3:0] ^ d[7:4] ^ {3'b000, l[8]};
    endfunction

    wire [3:0] vic_color = color_at(dot, row);

    always @(posedge clk) begin
        if (pix_en) begin
            if (vx == 503) begin
                vx <= 0;
                vy <= (vy == 311) ? 0 : vy + 1;
            end else begin
                vx <= vx + 1;
            end
        end
    end

    video_scandoubler #(.X_FIRST(X_FIRST), .Y_FIRST(Y_FIRST)) dut (
        .clk     (clk),
        .rst     (rst),
        .pix_en  (pix_en),
        .color   (vic_color),
        .hblank  (vic_hblank),
        .vblank  (vic_vblank),
        .r_q     (r),
        .g_q     (g),
        .b_q     (b),
        .de_q    (de),
        .hsync_q (hsync),
        .vsync_q (vsync)
    );

    // Eigene Abschrift der Farbtabelle (Palette von Pepto)
    function [23:0] rgb_of(input [3:0] color);
        case (color)
            4'd0:  rgb_of = 24'h000000;
            4'd1:  rgb_of = 24'hFFFFFF;
            4'd2:  rgb_of = 24'h68372B;
            4'd3:  rgb_of = 24'h70A4B2;
            4'd4:  rgb_of = 24'h6F3D86;
            4'd5:  rgb_of = 24'h588D43;
            4'd6:  rgb_of = 24'h352879;
            4'd7:  rgb_of = 24'hB8C76F;
            4'd8:  rgb_of = 24'h6F4F25;
            4'd9:  rgb_of = 24'h433900;
            4'd10: rgb_of = 24'h9A6759;
            4'd11: rgb_of = 24'h444444;
            4'd12: rgb_of = 24'h6C6C6C;
            4'd13: rgb_of = 24'h9AD284;
            4'd14: rgb_of = 24'h6C5EB5;
            4'd15: rgb_of = 24'h959595;
        endcase
    endfunction

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                if (errors < 20) $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    // --- Messung am Ausgang: ein Durchlauf pro Takt --------------------------
    integer cyc        = 0;
    integer hs_rise    = 0;
    integer vs_rise    = 0;
    integer de_rise    = 0;
    integer out_x      = 0;     // sichtbarer Punkt in der Zeile
    integer out_y      = -1;    // sichtbare Zeile im Bild
    integer frames     = 0;
    integer checked    = 0;
    reg     seen_hs    = 1'b0;
    reg     seen_vs    = 1'b0;
    reg     de_prev    = 1'b0;
    reg     hsync_prev = 1'b0;
    reg     vsync_prev = 1'b0;
    reg     measure    = 1'b0;

    always @(negedge clk) begin
        if (measure) begin
            cyc = cyc + 1;

            if (hsync && !hsync_prev) begin
                if (seen_hs) expect_eq(cyc - hs_rise, 1008, "Zeilenlaenge");
                hs_rise = cyc;
                seen_hs = 1'b1;
            end
            if (!hsync && hsync_prev && seen_hs) expect_eq(cyc - hs_rise, 96, "hsync-Breite");

            if (vsync && !vsync_prev) begin
                if (seen_vs) begin
                    expect_eq(cyc - vs_rise, 1008 * 624, "Bildlaenge");
                    expect_eq(out_y + 1, H, "sichtbare Zeilen pro Bild");
                    frames = frames + 1;
                end
                vs_rise = cyc;
                seen_vs = 1'b1;
                out_y   = -1;
            end
            if (!vsync && vsync_prev && seen_vs) expect_eq(cyc - vs_rise, 1008 * 6, "vsync-Breite");

            if (de && !de_prev) begin
                de_rise = cyc;
                out_x   = 0;
                out_y   = out_y + 1;
            end
            if (!de && de_prev && de_rise != 0) expect_eq(cyc - de_rise, W, "sichtbare Punkte pro Zeile");

            // 3. und 4. Farbe, erst ab dem ersten vollständigen Bild
            if (seen_vs && frames >= 1) begin
                if (de) begin
                    checked = checked + 1;
                    if ({r, g, b} !== rgb_of(color_at(X_FIRST + out_x / 2, Y_FIRST + out_y / 2))) begin
                        if (errors < 20)
                            $display("FAIL: Punkt (%0d,%0d) ist %h, erwartet %h", out_x, out_y, {r, g, b},
                                     rgb_of(color_at(X_FIRST + out_x / 2, Y_FIRST + out_y / 2)));
                        errors = errors + 1;
                    end
                end else if ({r, g, b} !== 24'h000000) begin
                    if (errors < 20) $display("FAIL: Farbe %h ausserhalb des Bildes bei t=%0t", {r, g, b}, $time);
                    errors = errors + 1;
                end
            end
            if (de) out_x = out_x + 1;

            de_prev    = de;
            hsync_prev = hsync;
            vsync_prev = vsync;
        end
    end

    initial begin
        // Nur den Anfang aufzeichnen, sonst wird die Datei riesig.
        $dumpfile("tb/build/tb_video_scandoubler.vcd");
        $dumpvars(0, tb_video_scandoubler);
        #400000 $dumpoff;
    end

    initial begin
        repeat (8) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // Das erste Bild nach dem Reset ist noch nicht richtig ausgerichtet
        // (der Verdoppler kennt den Bildanfang erst nach der ersten
        // Bildlücke). Gemessen wird deshalb ab dem zweiten vsync.
        @(posedge vsync);
        @(posedge vsync);
        @(negedge vsync);
        measure = 1'b1;

        wait (frames == 2);

        if (checked < W * H) begin
            $display("FAIL: nur %0d sichtbare Punkte geprueft", checked);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS: tb_video_scandoubler");
        else             $display("FAIL: tb_video_scandoubler (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: tb_video_scandoubler Timeout (Bilder=%0d)", frames);
        $finish;
    end

endmodule

`default_nettype wire
