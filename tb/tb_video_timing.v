// tb_video_timing — selbstprüfende Testbench für video_timing (640x480).
//
// Misst das Signal von außen, so wie ein Monitor es sieht, über gut zwei
// Bilder:
// 1. Zeile: Abstand der hsync-Impulse 800 Takte, Impulsbreite 96,
//    sichtbarer Teil 640, danach 16 Takte Pause bis zum hsync.
// 2. Bild: Abstand der vsync-Impulse 525 Zeilen, Impulsbreite 2 Zeilen,
//    480 sichtbare Zeilen, davor 33 Zeilen Pause nach dem vsync.
// 3. Nach Reset startet der Strahl bei (0,0).
// 4. Bei en = 0 bleibt der Strahl stehen.

`timescale 1ns / 1ps
`default_nettype none

module tb_video_timing;

    localparam H_TOTAL = 800;
    localparam V_TOTAL = 525;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         en  = 1'b1;
    wire [11:0] x;
    wire [11:0] y;
    wire        de;
    wire        hsync;
    wire        vsync;

    integer errors = 0;

    video_timing dut (
        .clk   (clk),
        .rst   (rst),
        .en    (en),
        .x_q   (x),
        .y_q   (y),
        .de    (de),
        .hsync (hsync),
        .vsync (vsync)
    );

    always #20 clk = ~clk;

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    // --- Messung: ein Durchlauf pro Takt ------------------------------------
    integer cyc          = 0;
    integer hs_rise      = 0;
    integer vs_rise      = 0;
    integer vs_fall      = 0;
    integer de_rise      = 0;
    integer de_fall      = 0;
    integer de_lines     = 0;   // sichtbare Zeilen seit dem letzten vsync
    integer frames       = 0;   // vollständig vermessene Bilder
    reg     seen_hs      = 1'b0;
    reg     seen_vs      = 1'b0;
    reg     de_this_line = 1'b0;
    reg     de_prev      = 1'b0;
    reg     hsync_prev   = 1'b0;
    reg     vsync_prev   = 1'b0;
    reg     measure      = 1'b1;   // 0: Messung beendet (Tests 3 und 4)

    always @(negedge clk) begin
        if (!rst && measure) begin
            cyc = cyc + 1;

            if (de && !de_prev) begin
                de_rise = cyc;
                if (seen_vs && de_lines == 0)
                    expect_eq(cyc - vs_fall, 33 * H_TOTAL, "Pause nach vsync");
                de_lines = de_lines + 1;
            end
            if (!de && de_prev) begin
                expect_eq(cyc - de_rise, 640, "sichtbare Pixel pro Zeile");
                de_fall      = cyc;
                de_this_line = 1'b1;
            end

            if (hsync && !hsync_prev) begin
                if (seen_hs)      expect_eq(cyc - hs_rise, H_TOTAL, "Zeilenlaenge");
                if (de_this_line) expect_eq(cyc - de_fall, 16, "Pause vor hsync");
                hs_rise      = cyc;
                seen_hs      = 1'b1;
                de_this_line = 1'b0;
            end
            if (!hsync && hsync_prev)
                expect_eq(cyc - hs_rise, 96, "hsync-Breite");

            if (vsync && !vsync_prev) begin
                if (seen_vs) begin
                    expect_eq(cyc - vs_rise, H_TOTAL * V_TOTAL, "Bildlaenge");
                    expect_eq(de_lines, 480, "sichtbare Zeilen pro Bild");
                    frames = frames + 1;
                end
                vs_rise  = cyc;
                seen_vs  = 1'b1;
                de_lines = 0;
            end
            if (!vsync && vsync_prev) begin
                expect_eq(cyc - vs_rise, 2 * H_TOTAL, "vsync-Breite");
                vs_fall = cyc;
            end

            de_prev    = de;
            hsync_prev = hsync;
            vsync_prev = vsync;
        end
    end

    initial begin
        // Nur die ersten Zeilen aufzeichnen, sonst wird die Datei riesig.
        $dumpfile("tb/build/tb_video_timing.vcd");
        $dumpvars(0, tb_video_timing);
        #200000 $dumpoff;
    end

    initial begin
        repeat (3) @(posedge clk);
        #1;
        expect_eq(x, 0, "x im Reset");
        expect_eq(y, 0, "y im Reset");
        expect_eq(de, 1, "de bei (0,0)");
        @(negedge clk) rst = 1'b0;

        wait (frames == 2);
        @(negedge clk);

        // 3. Reset mitten im Bild
        measure = 1'b0;
        rst = 1'b1;
        @(posedge clk); #1;
        expect_eq(x, 0, "x nach Reset");
        expect_eq(y, 0, "y nach Reset");

        // 4. Taktfreigabe
        @(negedge clk) rst = 1'b0;
        repeat (5) @(negedge clk);
        expect_eq(x, 5, "x nach 5 Takten");
        en = 1'b0;
        repeat (5) @(negedge clk);
        expect_eq(x, 5, "x bei en=0");

        if (errors == 0) $display("PASS: tb_video_timing");
        else             $display("FAIL: tb_video_timing (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #80_000_000;
        $display("FAIL: tb_video_timing Timeout (Bilder=%0d)", frames);
        $finish;
    end

endmodule

`default_nettype wire
