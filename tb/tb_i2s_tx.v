// tb_i2s_tx — selbstprüfende Testbench für i2s_tx.
//
// Die Testbench spielt den Empfänger: Sie übernimmt SDATA mit jeder
// steigenden Flanke von SCLK und setzt daraus die Abtastwerte zusammen.
// 1. Die empfangenen Werte stimmen mit den gesendeten überein (links und
//    rechts, positive und negative Werte, höchstes Bit zuerst, ein Takt
//    nach dem Wechsel von LRCLK).
// 2. Ein Paar besteht aus 64 SCLK-Takten; die unbenutzten Bitplätze sind 0.
// 3. Leitungen wechseln nur bei fallender Flanke von SCLK.
// 4. Ein Paar dauert genau 640 Systemtakte (16 Paare = 10240); jede
//    SCLK-Hälfte ist 5 Takte lang.
// 5. MCLK hat eine Periode von 5 Systemtakten, also zwei je SCLK-Hälfte, und
//    SCLK wechselt mit der steigenden Flanke von MCLK.

`timescale 1ns / 1ps
`default_nettype none

module tb_i2s_tx;

    reg               clk   = 1'b0;
    reg               rst   = 1'b1;
    reg signed [15:0] left  = 16'sd0;
    reg signed [15:0] right = 16'sd0;
    wire              mclk;
    wire              sclk;
    wire              lrclk;
    wire              sdata;

    integer errors = 0;

    i2s_tx dut (
        .clk     (clk),
        .rst     (rst),
        .left    (left),
        .right   (right),
        .mclk_q  (mclk),
        .sclk_q  (sclk),
        .lrclk_q (lrclk),
        .sdata_q (sdata)
    );

    always #10 clk = ~clk;

    task fail(input [255:0] what);
        begin
            if (errors < 20) $display("FAIL: %0s bei t=%0t", what, $time);
            errors = errors + 1;
        end
    endtask

    // --- Empfänger ----------------------------------------------------------
    reg [31:0] shift_l  = 32'd0;
    reg [31:0] shift_r  = 32'd0;
    reg [31:0] got_l    = 32'd0;    // letztes vollständiges Paar
    reg [31:0] got_r    = 32'd0;
    integer    n_frames = 0;
    integer    n_bits   = 0;        // SCLK-Takte im laufenden Paar
    reg        lrclk_at_rise = 1'b1;

    always @(posedge sclk) begin
        if (!rst) begin
            if (lrclk_at_rise && !lrclk) begin
                // neues Paar beginnt: das vorige ist vollständig
                if (n_frames > 0 && n_bits != 64) fail("Paar hat nicht 64 SCLK-Takte");
                got_l    = shift_l;
                got_r    = shift_r;
                n_frames = n_frames + 1;
                n_bits   = 0;
            end
            if (!lrclk) shift_l = {shift_l[30:0], sdata};
            else        shift_r = {shift_r[30:0], sdata};
            n_bits        = n_bits + 1;
            lrclk_at_rise = lrclk;
        end
    end

    // 3. Wechsel nur bei SCLK = 0 (also nach der fallenden Flanke)
    always @(lrclk or sdata) begin
        if (!rst && sclk !== 1'b0) fail("LRCLK oder SDATA wechselt bei SCLK = 1");
    end

    // 4. Länge der SCLK-Hälften in Systemtakten
    integer half_len = 0;
    reg     sclk_prev = 1'b0;

    always @(negedge clk) begin
        if (!rst) begin
            if (sclk != sclk_prev) begin
                if (half_len != 0 && half_len != 5) fail("SCLK-Haelfte ist nicht 5 Takte lang");
                half_len = 1;
            end else begin
                half_len = half_len + 1;
            end
            sclk_prev = sclk;
        end
    end

    // 5. MCLK: Periode und Lage zu SCLK
    integer mclk_len  = 0;
    reg     mclk_prev = 1'b0;
    reg     sclk_at_mclk = 1'b0;

    always @(negedge clk) begin
        if (!rst) begin
            if (mclk && !mclk_prev) begin
                if (mclk_len != 0 && mclk_len != 5) fail("MCLK-Periode ist nicht 5 Takte lang");
                if (sclk == sclk_at_mclk && mclk_len != 0) fail("SCLK wechselt nicht mit der steigenden MCLK-Flanke");
                sclk_at_mclk = sclk;
                mclk_len = 1;
            end else begin
                mclk_len = mclk_len + 1;
            end
            mclk_prev = mclk;
        end
    end

    // Erwartetes Bild eines Kanals im 32-Bit-Fenster: 1 Bit Vorlauf, 16 Bit
    // Daten, 15 Bit Null.
    function [31:0] slot(input [15:0] value);
        slot = {1'b0, value, 15'b0};
    endfunction

    // Legt neue Werte an und wartet, bis ein Paar damit vollständig
    // empfangen wurde.
    task send_and_check(input signed [15:0] l, input signed [15:0] r, input [255:0] what);
        integer start;
        begin
            @(negedge clk);
            left = l; right = r;
            start = n_frames;
            wait (n_frames >= start + 3);   // übernommen, gesendet, abgeschlossen
            if (got_l !== slot(l)) begin
                $display("FAIL: %0s links: %h, erwartet %h", what, got_l, slot(l));
                errors = errors + 1;
            end
            if (got_r !== slot(r)) begin
                $display("FAIL: %0s rechts: %h, erwartet %h", what, got_r, slot(r));
                errors = errors + 1;
            end
        end
    endtask

    integer t_start, f_start;

    initial begin
        $dumpfile("tb/build/tb_i2s_tx.vcd");
        $dumpvars(0, tb_i2s_tx);

        repeat (4) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 1. und 2. Werte
        send_and_check(16'sh1234, 16'shABCD,  "Muster");
        send_and_check(16'sh7FFF, -16'sh8000, "Grenzwerte");
        send_and_check(-16'sd1,   16'sd1,     "kleine Werte");
        send_and_check(16'sd0,    16'sd0,     "Null");

        // 4. Rate: 16 Paare = 10240 Systemtakte
        wait (n_frames % 16 == 0);
        @(posedge sclk);
        f_start = n_frames;
        t_start = $time;
        wait (n_frames == f_start + 16);
        @(posedge sclk);
        if ((($time - t_start) / 20) != 10240) begin
            $display("FAIL: 16 Paare dauern %0d Takte, erwartet 10240", ($time - t_start) / 20);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: tb_i2s_tx");
        else             $display("FAIL: tb_i2s_tx (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: tb_i2s_tx Timeout (Paare=%0d)", n_frames);
        $finish;
    end

endmodule

`default_nettype wire
