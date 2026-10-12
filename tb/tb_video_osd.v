// tb_video_osd — selbstprüfende Testbench für video_osd.
//
// Die Testbench erzeugt ein kleines Bild (540 x 262 sichtbar, gerade groß
// genug für das Fenster von 512 x 256 an der Stelle X0 = 20, Y0 = 4) mit
// einer Farbe, die von der Lage abhängt, und rechnet für jeden Bildpunkt
// nach, was drei Takte später herauskommen muss. Der Zeichensatz ist das
// Test-ROM banktest_char.hex: Jedes Zeichen besteht aus acht gleichen Zeilen
// mit dem eigenen Code als Muster — so lässt sich jedes Pixel vorhersagen.
// Geprüft wird über je ein ganzes Bild:
//   1. Fenster unsichtbar: Das Bild kommt unverändert heraus, drei Takte
//      später, samt de, hsync und vsync.
//   2. Fenster sichtbar: Im Fenster ist ein gesetztes Pixel weiß, jedes
//      andere das Bild darunter auf ein Viertel abgedunkelt; außerhalb
//      bleibt das Bild unverändert. Jedes Zeichen ist 16 x 16 groß und
//      steht an seinem Platz.
//   3. Ein Zeichen ändern: nur dieses Feld ändert sich.
//   4. Schreiben ohne Byte 0 (byteenable) ändert nichts; wieder unsichtbar
//      schalten stellt das Bild wieder her.

`timescale 1ns / 1ps
`default_nettype none

module tb_video_osd;

    localparam H_ACTIVE = 540, H_BLANK = 12;
    localparam V_ACTIVE = 262, V_BLANK = 3;
    localparam X0 = 20, Y0 = 4;

    reg         clk_av = 1'b0;
    reg         rst_av = 1'b1;
    reg  [9:0]  av_address = 10'd0;
    reg         av_write_r = 1'b0;
    reg  [31:0] av_writedata = 32'd0;
    reg  [3:0]  av_byteenable = 4'b0000;

    reg         clk = 1'b0;
    reg  [23:0] rgb = 24'd0;
    reg         de = 1'b0;
    reg         hsync = 1'b0;
    reg         vsync = 1'b0;
    wire [23:0] rgb_o;
    wire        de_o, hsync_o, vsync_o;

    integer     errors = 0;
    integer     n_checked = 0;      // geprüfte Bildpunkte im Fenster
    integer     i;

    video_osd #(.CHAR_FILE("sw/asm/build/banktest_char.hex"), .X0(X0), .Y0(Y0)) dut (
        .clk_av         (clk_av),
        .rst_av         (rst_av),
        .avs_address    (av_address),
        .avs_write      (av_write_r),
        .avs_writedata  (av_writedata),
        .avs_byteenable (av_byteenable),
        .clk            (clk),
        .rgb            (rgb),
        .de             (de),
        .hsync          (hsync),
        .vsync          (vsync),
        .rgb_q          (rgb_o),
        .de_q           (de_o),
        .hsync_q        (hsync_o),
        .vsync_q        (vsync_o)
    );

    always #5      clk_av = ~clk_av;
    always #15.873 clk    = ~clk;

    // --- Modell: Textspeicher und erwartetes Bild ---------------------------
    reg [7:0] text [0:511];
    reg       visible = 1'b0;       // was die Testbench zuletzt eingestellt hat
    reg       check = 1'b0;         // Bild wird gerade geprüft

    function [23:0] color(input integer x, input integer y);
        color = {x[7:0], y[7:0], x[7:0] ^ 8'hA5};
    endfunction

    function [23:0] expected(input integer x, input integer y);
        integer    wx, wy;
        reg [7:0]  c;
        reg [23:0] p;
        begin
            p        = color(x, y);
            expected = p;
            if (visible && x >= X0 && x < X0 + 512 && y >= Y0 && y < Y0 + 256) begin
                wx = x - X0;
                wy = y - Y0;
                c  = text[(wy / 16) * 32 + wx / 16];
                // Test-ROM: jede Zeile des Zeichens ist sein Code; das linke
                // Pixel ist das oberste Bit, jedes Pixel doppelt breit.
                if (c[7 - (wx / 2) % 8]) expected = 24'hFFFFFF;
                else expected = {2'b00, p[23:18], 2'b00, p[15:10], 2'b00, p[7:2]};
            end
        end
    endfunction

    // Bildgenerator; schiebt den erwarteten Wert drei Takte mit.
    integer    px = 0, py = 0;
    reg [23:0] want [0:2];
    reg [2:0]  want_de = 3'b000, want_hs = 3'b000, want_vs = 3'b000;
    reg [2:0]  want_win = 3'b000;

    always @(negedge clk) begin
        // prüfen, was jetzt am Ausgang liegt (Eingang von vor drei Takten)
        if (check) begin
            if (de_o !== want_de[2] || hsync_o !== want_hs[2] || vsync_o !== want_vs[2]) begin
                if (errors < 20) $display("FAIL: de/hsync/vsync nicht drei Takte verzoegert, t=%0t", $time);
                errors = errors + 1;
            end
            if (want_de[2] && rgb_o !== want[2]) begin
                if (errors < 20) $display("FAIL: Farbe %06x, erwartet %06x, t=%0t", rgb_o, want[2], $time);
                errors = errors + 1;
            end
            if (want_de[2] && want_win[2]) n_checked = n_checked + 1;
        end

        // nächsten Bildpunkt anlegen
        want[2]  = want[1];
        want[1]  = want[0];
        want_de  = {want_de[1:0],  1'b0};
        want_hs  = {want_hs[1:0],  1'b0};
        want_vs  = {want_vs[1:0],  1'b0};
        want_win = {want_win[1:0], 1'b0};

        de    = (px < H_ACTIVE) && (py < V_ACTIVE);
        hsync = (px >= H_ACTIVE + 2) && (px < H_ACTIVE + 8);
        vsync = (py == V_ACTIVE + 1);
        rgb   = de ? color(px, py) : 24'h123456;

        want[0]     = expected(px, py);
        want_de[0]  = de;
        want_hs[0]  = hsync;
        want_vs[0]  = vsync;
        want_win[0] = visible && px >= X0 && px < X0 + 512 && py >= Y0 && py < Y0 + 256;

        px = px + 1;
        if (px == H_ACTIVE + H_BLANK) begin
            px = 0;
            py = py + 1;
            if (py == V_ACTIVE + V_BLANK) py = 0;
        end
    end

    task av_write(input [9:0] addr, input [31:0] value, input [3:0] be);
        begin
            @(negedge clk_av);
            av_address    = addr;
            av_writedata  = value;
            av_byteenable = be;
            av_write_r    = 1'b1;
            @(negedge clk_av);
            av_write_r    = 1'b0;
        end
    endtask

    // Die beiden Tasks schauen bei der steigenden Flanke auf die Zähler des
    // Bildgenerators, der bei der fallenden arbeitet. Bei derselben Flanke
    // wäre nicht festgelegt, wer zuerst an der Reihe ist.

    // Wartet auf den Beginn der Bildlücke (dort ändert die Testbench Text
    // und Sichtbarkeit, damit Modell und Modul dasselbe Bild sehen).
    task wait_vblank;
        begin
            @(posedge clk);
            while (!(py == V_ACTIVE && px == 4)) @(posedge clk);
        end
    endtask

    // Prüft ein ganzes Bild.
    task check_frame;
        begin
            while (!(py == 0 && px == 0)) @(posedge clk);
            repeat (4) @(posedge clk);
            check = 1'b1;
            while (!(py == V_ACTIVE && px == 0)) @(posedge clk);
            check = 1'b0;
        end
    endtask

    task expect_eq(input integer got, input integer want_v, input [255:0] what);
        begin
            if (got !== want_v) begin
                $display("FAIL: %0s: %0d, erwartet %0d", what, got, want_v);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_video_osd.vcd");
        $dumpvars(1, tb_video_osd);

        repeat (4) @(posedge clk_av);
        @(negedge clk_av) rst_av = 1'b0;

        // Text: jedes Feld ein anderer, ungerader Code (Zeichen 0 hat im
        // Test-ROM eine abweichende erste Zeile)
        wait_vblank;
        for (i = 0; i < 512; i = i + 1) begin
            text[i] = (i * 5 + 3) | 1;
            av_write(10'd512 + i[9:0], {24'd0, text[i]}, 4'b1111);
        end

        // 1. unsichtbar
        check_frame;
        expect_eq(n_checked, 0, "1. kein Fenster");

        // 2. sichtbar
        wait_vblank;
        av_write(10'd0, 32'd1, 4'b1111);
        visible = 1'b1;
        check_frame;
        expect_eq(n_checked, 512 * 256, "2. Bildpunkte im Fenster");

        // 3. ein Zeichen ändern (Zeile 9, Spalte 17), invers
        wait_vblank;
        text[9 * 32 + 17] = 8'hC3;
        av_write(10'd512 + 10'd305, 32'h0000_00C3, 4'b1111);
        n_checked = 0;
        check_frame;
        expect_eq(n_checked, 512 * 256, "3. Bildpunkte im Fenster");

        // 4. Schreiben ohne Byte 0 ändert nichts; dann unsichtbar
        wait_vblank;
        av_write(10'd512 + 10'd305, 32'h0000_0055, 4'b1110);
        av_write(10'd0, 32'd0, 4'b1110);
        check_frame;
        wait_vblank;
        av_write(10'd0, 32'd0, 4'b1111);
        visible = 1'b0;
        n_checked = 0;
        check_frame;
        expect_eq(n_checked, 0, "4. wieder kein Fenster");

        if (errors == 0) $display("PASS: tb_video_osd");
        else             $display("FAIL: tb_video_osd (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #600_000_000;
        $display("FAIL: tb_video_osd Timeout");
        $finish;
    end

endmodule

`default_nettype wire
