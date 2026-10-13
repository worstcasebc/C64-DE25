// tb_video_upscaler — selbstprüfende Testbench für video_upscaler.
//
// Zwei Prüflinge:
//   u_real   mit den Werten für 720p50. Geprüft wird nur das Raster:
//            1. 1980 Takte pro Zeile, 750 Zeilen, sichtbar 1280 x 720,
//               hsync 40 Takte (440 nach dem Zeilenende), vsync 5 Zeilen
//               (5 Zeilen nach dem Bildende).
//   u_small  ein verkleinertes Abbild mit denselben Verhältnissen (Zeilen
//            pro Bild, Lage des Fensters, Tempo von Schreiber und Leser),
//            damit viele Bilder in kurzer Zeit laufen. Die Testbench spielt
//            den VIC-II; die Farbe jedes Pixels hängt von seiner Position und
//            von der Nummer des Bildes ab. So lässt sich für jeden
//            Ausgangspunkt nachrechnen, was erscheinen muss — und aus
//            welchem Bild des C64 er stammt.
//            2. Jeder Punkt zeigt das richtige Pixel, 3 x 3 Bildpunkte groß;
//               der Rand neben dem Fenster und alles außerhalb des
//               sichtbaren Bereichs ist schwarz.
//            3. Kein zerrissenes Bild: Alle Punkte eines Ausgangsbildes
//               stammen aus demselben Bild des C64.
//            4. Die Bilder folgen der Reihe nach. Ist der C64 schneller,
//               wird gelegentlich eines ausgelassen; ist er langsamer, eines
//               wiederholt. Nie geht es rückwärts.
//            Dazu laufen drei Durchgänge, in denen die beiden Takte
//            gegeneinander wandern: C64 2 % schneller, C64 1 % langsamer,
//            C64 0,8 % schneller (auf dem Board sind es 0,16 %). In jedem
//            wandert der Schreiber einmal ganz am Leser vorbei.

`timescale 1ns / 1ps
`default_nettype none

module tb_video_upscaler;

    // Verkleinertes Abbild: VIC-Raster 40 x 39, Fenster 16 x 30 ab (6, 5);
    // Ausgang 70 x 94, sichtbar 56 x 90, Fenster 48 x 90 mit 4 Punkten Rand.
    localparam S_HTOT = 40, S_VTOT = 39;
    localparam X_FIRST = 6, Y_FIRST = 5, SRC_W = 16, SRC_H = 30, SCALE = 3;
    localparam H_ACTIVE = 56, H_FP = 4, H_SYNC = 4, H_BP = 6;
    localparam V_ACTIVE = 90, V_FP = 1, V_SYNC = 1, V_BP = 2;
    localparam X_OFF = (H_ACTIVE - SRC_W * SCALE) / 2;

    reg  clk      = 1'b0;
    reg  clk_vid  = 1'b0;
    reg  clk_real = 1'b0;
    reg  rst      = 1'b1;
    reg  rst_vid  = 1'b1;
    real half_vid = 15.0;

    integer errors = 0;

    always #16        clk      = ~clk;          // 31,25 MHz
    always #(half_vid) clk_vid = ~clk_vid;
    // Für u_real zählt nur das Raster: schneller Takt, und nur so lange, bis
    // zwei Bilder gemessen sind (sonst bremst er die ganze Simulation).
    integer r_frames = 0;
    initial begin
        while (r_frames < 2) #1 clk_real = ~clk_real;
    end

    reg  [1:0] sub = 2'd0;
    wire       pix_en = (sub == 2'd3);
    always @(posedge clk) sub <= sub + 2'd1;

    // --- Der gespielte VIC-II ------------------------------------------------
    integer vx = 0, vy = 0, vframe = 0;
    wire vic_hblank = (vx >= 30 && vx < 36);
    wire vic_vblank = (vy >= 33 || vy < 2);

    // Position so, wie video_upscaler zählt (siehe tb_video_scandoubler).
    wire [8:0] dot     = (vx >= 30) ? vx - 30 : vx + S_HTOT - 30;
    wire [9:0] row_raw = (vx >= 30) ? vy + 1 : vy;
    wire [8:0] row     = (row_raw >= 34) ? row_raw - 34 : row_raw + S_VTOT - 34;

    function [3:0] color_at(input integer d, input integer l, input integer f);
        color_at = d + 3 * l + f;
    endfunction

    wire [3:0] vic_color = color_at(dot, row, vframe);

    always @(posedge clk) begin
        if (pix_en) begin
            // Mit dem Schritt nach (30, 33) beginnt für den Prüfling Zeile 0
            // eines neuen Bildes.
            if (vx == 29 && vy == 33) vframe <= vframe + 1;
            if (vx == S_HTOT - 1) begin
                vx <= 0;
                vy <= (vy == S_VTOT - 1) ? 0 : vy + 1;
            end else begin
                vx <= vx + 1;
            end
        end
    end

    wire [7:0] r, g, b;
    wire       de, hsync, vsync;

    video_upscaler #(
        .X_FIRST (X_FIRST), .Y_FIRST (Y_FIRST), .SRC_W (SRC_W), .SRC_H (SRC_H), .SCALE (SCALE),
        .H_ACTIVE (H_ACTIVE), .H_FP (H_FP), .H_SYNC (H_SYNC), .H_BP (H_BP),
        .V_ACTIVE (V_ACTIVE), .V_FP (V_FP), .V_SYNC (V_SYNC), .V_BP (V_BP)
    ) u_small (
        .clk     (clk),
        .rst     (rst),
        .pix_en  (pix_en),
        .color   (vic_color),
        .hblank  (vic_hblank),
        .vblank  (vic_vblank),
        .clk_vid (clk_vid),
        .rst_vid (rst_vid),
        .r_q     (r),
        .g_q     (g),
        .b_q     (b),
        .de_q    (de),
        .hsync_q (hsync),
        .vsync_q (vsync)
    );

    wire real_de, real_hsync, real_vsync;
    reg  rst_real = 1'b1;

    video_upscaler u_real (
        .clk     (clk),
        .rst     (rst),
        .pix_en  (pix_en),
        .color   (vic_color),
        .hblank  (vic_hblank),
        .vblank  (vic_vblank),
        .clk_vid (clk_real),
        .rst_vid (rst_real),
        .r_q     (),
        .g_q     (),
        .b_q     (),
        .de_q    (real_de),
        .hsync_q (real_hsync),
        .vsync_q (real_vsync)
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

    // Farbnummer zu einer RGB-Farbe; 16 = keine Farbe des C64
    function integer index_of(input [23:0] rgb);
        integer i;
        begin
            index_of = 16;
            for (i = 0; i < 16; i = i + 1)
                if (rgb_of(i[3:0]) === rgb) index_of = i;
        end
    endfunction

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                if (errors < 20) $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    // --- 1. Raster von u_real ------------------------------------------------
    integer rc = 0, r_hs_rise = 0, r_vs_rise = 0, r_de_rise = 0, r_de_fall = 0;
    integer r_lines = 0;
    reg     r_seen_hs = 1'b0, r_seen_vs = 1'b0;
    reg     r_de_prev = 1'b0, r_hs_prev = 1'b0, r_vs_prev = 1'b0;

    always @(negedge clk_real) begin
        rc = rc + 1;
        if (real_hsync && !r_hs_prev) begin
            if (r_seen_hs) expect_eq(rc - r_hs_rise, 1980, "720p: Zeilenlaenge");
            if (r_seen_vs && r_de_fall != 0 && rc - r_de_fall < 1980)
                expect_eq(rc - r_de_fall, 440, "720p: Abstand Zeilenende bis hsync");
            r_hs_rise = rc;
            r_seen_hs = 1'b1;
        end
        if (!real_hsync && r_hs_prev && r_seen_hs) expect_eq(rc - r_hs_rise, 40, "720p: hsync-Breite");

        if (real_vsync && !r_vs_prev) begin
            if (r_seen_vs) begin
                expect_eq(rc - r_vs_rise, 1980 * 750, "720p: Bildlaenge");
                expect_eq(r_lines, 720, "720p: sichtbare Zeilen");
                expect_eq(rc - r_de_fall, 700 + 5 * 1980, "720p: Abstand Bildende bis vsync");
                r_frames = r_frames + 1;
            end
            r_vs_rise = rc;
            r_seen_vs = 1'b1;
            r_lines   = 0;
        end
        if (!real_vsync && r_vs_prev && r_seen_vs) expect_eq(rc - r_vs_rise, 1980 * 5, "720p: vsync-Breite");

        if (real_de && !r_de_prev) begin
            r_de_rise = rc;
            r_lines   = r_lines + 1;
        end
        if (!real_de && r_de_prev) begin
            if (r_de_rise != 0) expect_eq(rc - r_de_rise, 1280, "720p: sichtbare Punkte pro Zeile");
            r_de_fall = rc;
        end

        r_de_prev = real_de;
        r_hs_prev = real_hsync;
        r_vs_prev = real_vsync;
    end

    // --- 2. bis 4. Inhalt von u_small ----------------------------------------
    integer out_x = 0, out_y = -1;
    integer frames = 0;         // geprüfte Ausgangsbilder im Durchgang
    integer frame_no = -1;      // Bild des C64, aus dem das Ausgangsbild stammt (mod 16)
    integer prev_no = -1;
    integer skipped = 0, repeated = 0, checked = 0;
    integer step_min = 1, step_max = 2;     // erlaubter Schritt von Bild zu Bild
    integer got, want, src_d, src_l, step;
    reg     de_prev = 1'b0, vsync_prev = 1'b0;
    reg     measure = 1'b0;

    always @(negedge clk_vid) begin
        if (vsync && !vsync_prev) begin
            if (measure && frame_no >= 0) begin
                expect_eq(out_y + 1, V_ACTIVE, "sichtbare Zeilen pro Bild");
                if (prev_no >= 0) begin
                    step = (frame_no - prev_no) & 15;
                    if (step < step_min || step > step_max) begin
                        if (errors < 20)
                            $display("FAIL: Bild %0d nach Bild %0d (Schritt %0d) bei t=%0t", frame_no, prev_no, step, $time);
                        errors = errors + 1;
                    end
                    if (step == 2) skipped  = skipped + 1;
                    if (step == 0) repeated = repeated + 1;
                end
                prev_no = frame_no;
                frames  = frames + 1;
            end
            out_y    = -1;
            frame_no = -1;
        end

        if (de && !de_prev) begin
            out_x = 0;
            out_y = out_y + 1;
        end
        if (!de && de_prev && measure) expect_eq(out_x, H_ACTIVE, "sichtbare Punkte pro Zeile");

        if (measure) begin
            if (de && out_x >= X_OFF && out_x < X_OFF + SRC_W * SCALE) begin
                src_d = X_FIRST + (out_x - X_OFF) / SCALE;
                src_l = Y_FIRST + out_y / SCALE;
                // Der erste Punkt des Fensters verrät, aus welchem Bild des
                // C64 dieses Ausgangsbild stammt; alle weiteren müssen aus
                // demselben sein.
                if (frame_no < 0) begin
                    got = index_of({r, g, b});
                    if (got < 16) frame_no = (got - src_d - 3 * src_l) & 15;
                end
                want = color_at(src_d, src_l, frame_no);
                checked = checked + 1;
                if ({r, g, b} !== rgb_of(want[3:0])) begin
                    if (errors < 20)
                        $display("FAIL: Punkt (%0d,%0d) zeigt Farbe %0d, erwartet %0d (Bild %0d) bei t=%0t",
                                 out_x, out_y, index_of({r, g, b}), want, frame_no, $time);
                    errors = errors + 1;
                end
            end else if ({r, g, b} !== 24'h000000) begin
                if (errors < 20) $display("FAIL: Farbe %h ausserhalb des Fensters bei t=%0t", {r, g, b}, $time);
                errors = errors + 1;
            end
        end
        if (de) out_x = out_x + 1;

        de_prev    = de;
        vsync_prev = vsync;
    end

    // Ein Durchgang: Reset, Takt des Lesers einstellen, n Bilder prüfen.
    task run(input real half, input integer n, input integer smin, input integer smax);
        begin
            measure = 1'b0;
            @(negedge clk)     rst     = 1'b1;
            @(negedge clk_vid) rst_vid = 1'b1;
            half_vid = half;
            step_min = smin;
            step_max = smax;
            repeat (8) @(posedge clk);
            @(negedge clk)     rst     = 1'b0;
            @(negedge clk_vid) rst_vid = 1'b0;
            // Die ersten Bilder nach dem Reset sind noch nicht vollständig.
            repeat (4) @(posedge vsync);
            @(negedge vsync);
            prev_no  = -1;
            frame_no = -1;
            frames   = 0;
            skipped  = 0;
            repeated = 0;
            measure  = 1'b1;
            wait (frames == n);
            measure  = 1'b0;
        end
    endtask

    initial begin
        // Nur den Anfang aufzeichnen, sonst wird die Datei riesig.
        $dumpfile("tb/build/tb_video_upscaler.vcd");
        $dumpvars(1, tb_video_upscaler);
        $dumpvars(0, u_small);
        #600000 $dumpoff;
    end

    initial begin
        repeat (8) @(posedge clk_real);
        @(negedge clk_real) rst_real = 1'b0;

        // Ein Bild des C64 dauert 40 * 39 * 4 * 32 ns = 199680 ns, ein
        // Ausgangsbild 70 * 94 * 2 * half_vid.
        run(15.5, 60, 1, 2);            // 203980 ns: C64 2,1 % schneller
        if (skipped == 0) begin
            $display("FAIL: C64 schneller, aber kein Bild ausgelassen");
            errors = errors + 1;
        end
        if (repeated != 0) begin
            $display("FAIL: C64 schneller, aber %0d Bilder wiederholt", repeated);
            errors = errors + 1;
        end

        run(15.0, 100, 0, 1);           // 197400 ns: C64 1,1 % langsamer
        if (repeated == 0) begin
            $display("FAIL: C64 langsamer, aber kein Bild wiederholt");
            errors = errors + 1;
        end

        run(15.3, 140, 1, 2);           // 201348 ns: C64 0,83 % schneller
        if (skipped != 1 && skipped != 2) begin
            $display("FAIL: C64 0,83 %% schneller: %0d Bilder ausgelassen, erwartet 1 oder 2", skipped);
            errors = errors + 1;
        end

        wait (r_frames == 2);

        if (checked < 280 * SRC_W * SCALE * V_ACTIVE) begin
            $display("FAIL: nur %0d Punkte geprueft", checked);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS: tb_video_upscaler");
        else             $display("FAIL: tb_video_upscaler (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: tb_video_upscaler Timeout (Bilder=%0d, 720p-Bilder=%0d)", frames, r_frames);
        $finish;
    end

endmodule

`default_nettype wire
