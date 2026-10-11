// tb_sid_tone — Testbench für den SID aus MiSTer (allein).
// Simulator: Questa
//
// Der SID hängt direkt an der Testbench, mit 32 Systemtakten pro CPU-Takt wie
// auf dem Board. Die Testbench spielt einen Ton auf Stimme 1 und prüft das
// Ausgangssignal:
// 1. Ohne Ton bleibt der Ausgang ruhig.
// 2. Sägezahn mit Frequenzwert $4000: Eine Schwingung dauert
//    2^24 / $4000 = 1024 CPU-Takte (961 Hz). Der Ausgang steigt gleichmäßig
//    und springt einmal pro Schwingung zurück.
// 3. Lautstärke 0 lässt den Ton verstummen.
// 4. Das Register $1B (Oszillator 3) lässt sich lesen und läuft mit.

`timescale 1ns / 1ps
`default_nettype none

module tb_sid_tone;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [4:0]  cyc = 5'd0;
    wire        ce_1m = (cyc == 5'd0);  // ein Takt pro CPU-Takt
    reg         cs = 1'b0;
    reg         we = 1'b0;
    reg  [4:0]  addr = 5'h00;
    reg  [7:0]  din = 8'h00;
    wire [7:0]  dout;
    wire [17:0] audio;
    wire [17:0] audio_r_unused;

    integer errors = 0;

    sid_top #(.MULTI_FILTERS(0), .DUAL(0)) dut (
        .reset       (rst),
        .clk         (clk),
        .ce_1m       (ce_1m),
        .cs          (cs),
        .we          (we),
        .addr        (addr),
        .data_in     (din),
        .data_out    (dout),
        .fc_offset_l (13'd0),
        .pot_x_l     (8'hFF),
        .pot_y_l     (8'hFF),
        .ext_in_l    (18'd0),
        .audio_l     (audio),
        .fc_offset_r (13'd0),
        .pot_x_r     (8'hFF),
        .pot_y_r     (8'hFF),
        .ext_in_r    (18'd0),
        .audio_r     (audio_r_unused),
        .filter_en   (1'b1),
        .mode        (1'b0),        // 6581
        .cfg         (2'b00),
        .ld_clk      (1'b0),
        .ld_addr     (12'd0),
        .ld_data     (16'd0),
        .ld_wr       (1'b0)
    );

    always #16 clk = ~clk;
    always @(posedge clk) cyc <= cyc + 5'd1;

    // Registerzugriff: einen Systemtakt lang, wie ein CPU-Schritt in soc_c64.
    task sid_write(input [4:0] a, input [7:0] d);
        begin
            wait (cyc == 5'd16); @(negedge clk);
            cs = 1'b1; we = 1'b1; addr = a; din = d;
            @(negedge clk);
            cs = 1'b0; we = 1'b0;
        end
    endtask

    task sid_read(input [4:0] a);       // Ergebnis steht danach in dout
        begin
            wait (cyc == 5'd16); @(negedge clk);
            cs = 1'b1; we = 1'b0; addr = a;
            @(negedge clk);
            cs = 1'b0;
        end
    endtask

    task expect_true(input cond, input [255:0] what);
        begin
            if (cond !== 1'b1) begin
                $display("FAIL: %0s bei t=%0t", what, $time);
                errors = errors + 1;
            end
        end
    endtask

    // --- Messung: einmal pro CPU-Takt ---------------------------------------
    integer        tick       = 0;
    integer        last_drop  = 0;
    integer        n_drops    = 0;
    integer        period_sum = 0;
    integer        n_periods  = 0;
    reg signed [17:0] prev    = 18'sd0;
    reg signed [17:0] lo      = 18'sd0;
    reg signed [17:0] hi      = 18'sd0;
    reg            measure    = 1'b0;

    wire signed [17:0] sample = audio;

    always @(posedge clk) begin
        if (ce_1m) begin
            tick = tick + 1;
            if (measure) begin
                if (sample < lo) lo = sample;
                if (sample > hi) hi = sample;
                // Rücksprung des Sägezahns: großer Sprung
                if ((sample - prev > 20000) || (prev - sample > 20000)) begin
                    if (n_drops > 0) begin
                        period_sum = period_sum + (tick - last_drop);
                        n_periods  = n_periods + 1;
                    end
                    last_drop = tick;
                    n_drops   = n_drops + 1;
                end
            end
            prev = sample;
        end
    end

    task start_measure;
        begin
            lo = sample; hi = sample; n_drops = 0; period_sum = 0; n_periods = 0;
            measure = 1'b1;
        end
    endtask

    reg [7:0] osc_a;

    initial begin
        repeat (200) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        repeat (20 * 32) @(posedge clk);

        // 1. Stille: Lautstärke 15, aber keine Stimme an
        sid_write(5'h18, 8'h0F);
        repeat (600 * 32) @(posedge clk);
        start_measure;
        repeat (600 * 32) @(posedge clk);
        measure = 1'b0;
        $display("Stille: Ausgang zwischen %0d und %0d", lo, hi);
        expect_true(hi - lo < 200, "Ausgang ohne Ton nicht ruhig");

        // 2. Sägezahn auf Stimme 1
        sid_write(5'h00, 8'h00);        // Frequenz low
        sid_write(5'h01, 8'h40);        // Frequenz high -> $4000
        sid_write(5'h05, 8'h00);        // Anschwellen/Abschwellen: sofort
        sid_write(5'h06, 8'hF0);        // Haltepegel: voll
        sid_write(5'h04, 8'h21);        // Sägezahn + Ton an
        repeat (2000 * 32) @(posedge clk);
        start_measure;
        repeat (6000 * 32) @(posedge clk);
        measure = 1'b0;
        $display("Ton: Ausgang zwischen %0d und %0d, %0d Spruenge, mittlere Periode %0d CPU-Takte",
                 lo, hi, n_drops, (n_periods > 0) ? period_sum / n_periods : 0);
        expect_true(hi - lo > 30000, "Ton zu leise oder fehlt");
        expect_true(n_drops >= 5 && n_drops <= 7, "Anzahl der Schwingungen in 6000 CPU-Takten");
        expect_true(n_periods > 0 && period_sum / n_periods >= 1022 && period_sum / n_periods <= 1026,
                    "Periode ist nicht 1024 CPU-Takte");

        // 4. Oszillator 3 lesen: Stimme 3 mit Sägezahn, zwei Werte im Abstand
        sid_write(5'h0E, 8'h00);
        sid_write(5'h0F, 8'h10);
        sid_write(5'h12, 8'h20);
        repeat (50 * 32) @(posedge clk);
        sid_read(5'h1B);
        osc_a = dout;
        repeat (100 * 32) @(posedge clk);
        sid_read(5'h1B);
        expect_true(dout != osc_a, "Oszillator 3 laeuft nicht");

        // 3. Lautstärke 0
        sid_write(5'h18, 8'h00);
        repeat (1000 * 32) @(posedge clk);
        start_measure;
        repeat (3000 * 32) @(posedge clk);
        measure = 1'b0;
        $display("Lautstaerke 0: Ausgang zwischen %0d und %0d", lo, hi);
        expect_true(hi - lo < 2000, "Ausgang bei Lautstaerke 0 nicht ruhig");

        if (errors == 0) $display("PASS: tb_sid_tone");
        else             $display("FAIL: tb_sid_tone (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("FAIL: tb_sid_tone Timeout");
        $finish;
    end

endmodule

`default_nettype wire
