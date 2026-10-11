// tb_video_colorbars — selbstprüfende Testbench für video_colorbars.
//
// 1. Balkenfarben: für jedes x einer Zeile mitten im Bild.
// 2. Weißer Rand: erste/letzte Zeile und erste/letzte Spalte.
// 3. Außerhalb des sichtbaren Bereichs (de = 0) ist die Farbe Schwarz.
// 4. de/hsync/vsync erscheinen zusammen mit der Farbe einen Takt später.
// 5. Bei en = 0 bleiben die Ausgänge stehen.

`timescale 1ns / 1ps
`default_nettype none

module tb_video_colorbars;

    reg         clk   = 1'b0;
    reg         en    = 1'b1;
    reg  [11:0] x     = 12'd0;
    reg  [11:0] y     = 12'd0;
    reg         de    = 1'b0;
    reg         hsync = 1'b0;
    reg         vsync = 1'b0;
    wire [7:0]  r;
    wire [7:0]  g;
    wire [7:0]  b;
    wire        de_out;
    wire        hsync_out;
    wire        vsync_out;

    integer errors = 0;
    integer i;

    localparam [23:0] WHITE = 24'hFFFFFF, YELLOW  = 24'hFFFF00, CYAN = 24'h00FFFF,
                      GREEN = 24'h00FF00, MAGENTA = 24'hFF00FF, RED  = 24'hFF0000,
                      BLUE  = 24'h0000FF, BLACK   = 24'h000000;

    video_colorbars dut (
        .clk     (clk),
        .en      (en),
        .x       (x),
        .y       (y),
        .de      (de),
        .hsync   (hsync),
        .vsync   (vsync),
        .r_q     (r),
        .g_q     (g),
        .b_q     (b),
        .de_q    (de_out),
        .hsync_q (hsync_out),
        .vsync_q (vsync_out)
    );

    always #10 clk = ~clk;

    function [23:0] bar_color(input integer n);
        case (n)
            0:       bar_color = WHITE;
            1:       bar_color = YELLOW;
            2:       bar_color = CYAN;
            3:       bar_color = GREEN;
            4:       bar_color = MAGENTA;
            5:       bar_color = RED;
            6:       bar_color = BLUE;
            default: bar_color = BLACK;
        endcase
    endfunction

    // Legt eine Position an, wartet eine Flanke und prüft Farbe und Signale.
    // sync = {hsync, vsync}
    task check(input integer px, input integer py, input visible, input [1:0] sync,
               input [23:0] want);
        begin
            @(negedge clk);
            x = px[11:0]; y = py[11:0]; de = visible; hsync = sync[1]; vsync = sync[0];
            @(posedge clk); #1;
            if ({r, g, b} !== want) begin
                $display("FAIL: (%0d,%0d) de=%b Farbe %h, erwartet %h", px, py, visible, {r, g, b}, want);
                errors = errors + 1;
            end
            if ({de_out, hsync_out, vsync_out} !== {visible, sync}) begin
                $display("FAIL: (%0d,%0d) {de,hsync,vsync}=%b, erwartet %b",
                         px, py, {de_out, hsync_out, vsync_out}, {visible, sync});
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_video_colorbars.vcd");
        $dumpvars(0, tb_video_colorbars);

        // 1. Balken in Zeile 240 (ohne die beiden Randspalten)
        for (i = 1; i < 639; i = i + 1) check(i, 240, 1'b1, 2'b00, bar_color(i / 80));

        // 2. Rand
        for (i = 0; i < 640; i = i + 1) begin
            check(i, 0,   1'b1, 2'b00, WHITE);
            check(i, 479, 1'b1, 2'b00, WHITE);
        end
        check(0,   240, 1'b1, 2'b00, WHITE);
        check(639, 240, 1'b1, 2'b00, WHITE);
        check(638, 1,   1'b1, 2'b00, BLACK);   // direkt neben dem Rand

        // 3. und 4. außerhalb des Bildes, mit Sync-Signalen
        check(656, 240, 1'b0, 2'b10, BLACK);
        check(0,   490, 1'b0, 2'b01, BLACK);
        check(700, 491, 1'b0, 2'b11, BLACK);

        // 5. en = 0: Ausgänge bleiben (zuletzt: Rot bei x = 400)
        check(400, 240, 1'b1, 2'b00, RED);
        @(negedge clk);
        en = 1'b0; x = 12'd0; de = 1'b0; hsync = 1'b1;
        @(posedge clk); #1;
        if ({r, g, b} !== RED || {de_out, hsync_out} !== 2'b10) begin
            $display("FAIL: Ausgaenge aendern sich bei en=0");
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: tb_video_colorbars");
        else             $display("FAIL: tb_video_colorbars (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
