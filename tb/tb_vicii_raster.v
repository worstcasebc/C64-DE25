// tb_vicii_raster — erste Testbench für den VIC-II aus FPGA64 (allein).
// Simulator: Questa
//
// Der VIC-II hängt hier direkt an der Testbench, ohne C64 drumherum. Die
// Testbench erzeugt die Freigaben so, wie es das MiSTer-Design tut: Ein
// CPU-Takt besteht aus 32 Systemtakten; in der ersten Hälfte (phi = 0)
// arbeitet der VIC-II am Bus, in der zweiten (phi = 1) die CPU. Jeder
// vierte Systemtakt ist ein Pixel.
// Geprüft wird das PAL-Raster des 6569 und der Registerzugriff:
// 1. Eine Zeile dauert 63 CPU-Takte = 504 Pixel, ein Bild 312 Zeilen.
// 2. $D020 schreiben und zurücklesen (obere Bits lesen als 1).
// 3. Das Raster-Register $D012 zählt pro Zeile um 1 weiter.
// 4. Bildschirm aus: Der VIC-II hält die CPU nie an (ba bleibt 1).
// 5. Bildschirm an ($D011 = $1B): In 25 Zeilen pro Bild ("Bad Lines") holt
//    der VIC-II die Zeichencodes und hält die CPU dafür an.
// 6. Ohne freigegebene Interrupts bleibt irq_n auf 1.

`timescale 1ns / 1ps
`default_nettype none

module tb_vicii_raster;

    reg         clk = 1'b0;
    reg         reset = 1'b1;
    reg  [4:0]  cyc = 5'd0;         // Systemtakt innerhalb des CPU-Takts, 0..31
    reg         phi = 1'b0;
    reg         ena_data = 1'b0;
    reg         ena_pixel = 1'b0;
    reg         cs = 1'b0;
    reg         we = 1'b0;
    reg  [5:0]  reg_addr = 6'h00;
    reg  [7:0]  reg_din = 8'h00;
    wire [7:0]  reg_dout;
    wire        ba;
    wire        irq_n;
    wire        hsync;
    wire        vsync;
    wire [3:0]  color;
    wire [13:0] vic_addr;

    integer errors = 0;

    video_vicii_656x #(
        .registeredAddress (1),
        .emulateRefresh    (1),
        .emulateLightpen   (0),
        .emulateGraphics   (1)
    ) dut (
        .clk         (clk),
        .phi         (phi),
        .enaData     (ena_data),
        .enaPixel    (ena_pixel),
        .baSync      (1'b0),
        .ba          (ba),
        .ba_dma      (),
        .mode6569    (1'b1),
        .mode6567old (1'b0),
        .mode6567R8  (1'b0),
        .mode6572    (1'b0),
        .turbo_en    (1'b0),
        .turbo_state (),
        .variant     (2'b00),
        .reset       (reset),
        .cs          (cs),
        .we          (we),
        .lp_n        (1'b1),
        .aRegisters  (reg_addr),
        .diRegisters (reg_din),
        .di          (8'h00),
        .diColor     (4'h0),
        .do          (reg_dout),
        .vicAddr     (vic_addr),
        .irq_n       (irq_n),
        .hSync       (hsync),
        .vSync       (vsync),
        .colorIndex  (color),
        .debugX      (),
        .debugY      (),
        .vicRefresh  (),
        .addrValid   ()
    );

    always #16 clk = ~clk;      // rund 31,25 MHz; der genaue Wert spielt hier keine Rolle

    // Freigaben wie in fpga64_sid_iec.vhd (MiSTer): alles Register.
    always @(posedge clk) begin
        cyc       <= cyc + 5'd1;
        ena_pixel <= (cyc[1:0] == 2'd2);
        ena_data  <= (cyc == 5'd14) || (cyc == 5'd30);
        if (cyc == 5'd15) phi <= 1'b1;
        if (cyc == 5'd31) phi <= 1'b0;
    end

    // --- Messung ------------------------------------------------------------
    integer pixels      = 0;    // Pixel seit dem letzten hsync
    integer lines       = 0;    // Zeilen seit dem letzten vsync
    integer frames      = 0;
    integer ba_low      = 0;    // CPU-Takte mit ba = 0 im laufenden Bild
    integer ba_low_last = 0;    // ... im zuletzt abgeschlossenen Bild
    reg     hsync_prev  = 1'b0;
    reg     vsync_prev  = 1'b0;
    reg     seen_h      = 1'b0;
    reg     seen_v      = 1'b0;
    reg     measure     = 1'b0;

    always @(posedge clk) begin
        if (measure && ena_pixel) begin
            pixels = pixels + 1;
            if (hsync && !hsync_prev) begin
                if (seen_h && pixels != 504) begin
                    if (errors < 10) $display("FAIL: Zeile hat %0d Pixel, erwartet 504", pixels);
                    errors = errors + 1;
                end
                seen_h = 1'b1;
                pixels = 0;
                lines  = lines + 1;
            end
            if (vsync && !vsync_prev) begin
                if (seen_v) begin
                    if (lines != 312) begin
                        $display("FAIL: Bild hat %0d Zeilen, erwartet 312", lines);
                        errors = errors + 1;
                    end
                    frames      = frames + 1;
                    ba_low_last = ba_low;
                end
                seen_v = 1'b1;
                lines  = 0;
                ba_low = 0;
            end
            hsync_prev = hsync;
            vsync_prev = vsync;
        end
        if (measure && cyc == 5'd31 && !ba) ba_low = ba_low + 1;
        if (measure && !irq_n) begin
            if (errors < 10) $display("FAIL: irq_n = 0 ohne freigegebenen Interrupt bei t=%0t", $time);
            errors = errors + 1;
        end
    end

    // --- Registerzugriffe: liegen einen ganzen CPU-Takt an -------------------
    task vic_write(input [5:0] a, input [7:0] d);
        begin
            wait (cyc == 5'd0); @(negedge clk);
            cs = 1'b1; we = 1'b1; reg_addr = a; reg_din = d;
            wait (cyc == 5'd31); @(negedge clk);
            wait (cyc == 5'd0);  @(negedge clk);
            cs = 1'b0; we = 1'b0;
        end
    endtask

    reg [7:0] rd;

    task vic_read(input [5:0] a);       // Ergebnis in rd
        begin
            wait (cyc == 5'd0); @(negedge clk);
            cs = 1'b1; we = 1'b0; reg_addr = a;
            wait (cyc == 5'd31); @(negedge clk);
            rd = reg_dout;
            wait (cyc == 5'd0);  @(negedge clk);
            cs = 1'b0;
        end
    endtask

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    reg [7:0] raster_a;
    integer   n;

    initial begin
        repeat (100) @(posedge clk);
        @(negedge clk) reset = 1'b0;
        measure = 1'b1;

        // Alle Register auf 0 setzen, so wie es das KERNAL beim Start tut.
        // Nach dem Einschalten ist ihr Inhalt unbestimmt.
        for (n = 0; n < 47; n = n + 1) vic_write(n[5:0], 8'h00);

        // 2. Registerzugriff
        vic_write(6'h20, 8'h05);
        vic_read(6'h20);
        expect_eq(rd, 8'hF5, "$D020 lesen");
        vic_write(6'h21, 8'h0B);
        vic_read(6'h21);
        expect_eq(rd, 8'hFB, "$D021 lesen");

        // 3. Raster-Register: zwei Lesezugriffe im Abstand einer Zeile
        vic_read(6'h12);
        raster_a = rd;
        repeat (63 * 32 - 64) @(posedge clk);   // vic_read selbst dauert 2 CPU-Takte
        vic_read(6'h12);
        expect_eq(rd, (raster_a + 8'd1) & 8'hFF, "$D012 eine Zeile spaeter");

        // 1. und 4. zwei ganze Bilder mit ausgeschaltetem Bildschirm
        wait (frames == 2);
        expect_eq(ba_low_last, 0, "CPU-Takte mit ba=0 bei Bildschirm aus");

        // 5. Bildschirm an: 25 Zeilen, 40 Spalten, Textmodus
        vic_write(6'h11, 8'h1B);
        wait (frames == 5);
        $display("Bildschirm an: ba war in %0d CPU-Takten pro Bild 0", ba_low_last);
        if (ba_low_last < 25 * 40 || ba_low_last > 25 * 46) begin
            $display("FAIL: ba=0 in %0d CPU-Takten pro Bild, erwartet 25 Zeilen zu je 40..46", ba_low_last);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: tb_vicii_raster");
        else             $display("FAIL: tb_vicii_raster (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #300_000_000;
        $display("FAIL: tb_vicii_raster Timeout (Bilder=%0d)", frames);
        $finish;
    end

endmodule

`default_nettype wire
