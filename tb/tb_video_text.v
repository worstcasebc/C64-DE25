// tb_video_text — selbstprüfende Testbench für video_text.
//
// video_timing liefert ein vollständiges Bild. Statt echter Speicher hängen
// zwei Rechenmodelle an den Anschlüssen: Der "Bildschirmspeicher" liefert
// einen Zeichencode, der aus der Adresse berechnet wird, das "Char-ROM" ein
// Muster aus Code und Pixelzeile. Die Testbench rechnet für jedes Pixel
// unabhängig aus, welche Farbe herauskommen muss, und vergleicht:
// 1. Rahmenfarbe oberhalb/unterhalb des Textbereichs, Schwarz außerhalb des
//    sichtbaren Bildes.
// 2. Im Textbereich: richtiges Zeichen (Adresse), richtige Pixelzeile und
//    richtiges Bit — jeweils in doppelter Größe.
// 3. de/hsync/vsync kommen passend zur Farbe drei Pixeltakte später.
// 4. Die Bildschirmadresse bleibt im Bereich $0400-$07E7.
// en wechselt wie im Top-Level in jedem Takt (Pixeltakt = halber Takt).

`timescale 1ns / 1ps
`default_nettype none

module tb_video_text;

    localparam [23:0] BORDER = 24'h6C5EB5, BG = 24'h352879, FG = 24'h6C5EB5;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         en  = 1'b0;
    wire [11:0] x;
    wire [11:0] y;
    wire        de;
    wire        hsync;
    wire        vsync;
    wire [15:0] ram_addr;
    reg  [7:0]  ram_dout = 8'h00;
    wire [11:0] char_addr;
    reg  [7:0]  char_dout = 8'h00;
    wire [7:0]  r;
    wire [7:0]  g;
    wire [7:0]  b;
    wire        de_out;
    wire        hsync_out;
    wire        vsync_out;

    integer errors   = 0;
    integer checked  = 0;
    integer frames   = 0;

    video_timing u_timing (
        .clk   (clk),
        .rst   (rst),
        .en    (en),
        .x_q   (x),
        .y_q   (y),
        .de    (de),
        .hsync (hsync),
        .vsync (vsync)
    );

    video_text dut (
        .clk       (clk),
        .en        (en),
        .x         (x),
        .y         (y),
        .de        (de),
        .hsync     (hsync),
        .vsync     (vsync),
        .ram_addr  (ram_addr),
        .ram_dout  (ram_dout),
        .char_addr (char_addr),
        .char_dout (char_dout),
        .r_q       (r),
        .g_q       (g),
        .b_q       (b),
        .de_q      (de_out),
        .hsync_q   (hsync_out),
        .vsync_q   (vsync_out)
    );

    always #10 clk = ~clk;
    always @(posedge clk) en <= ~en;

    // --- Rechenmodelle für die beiden Speicher ------------------------------
    function [7:0] code_at(input [15:0] address);
        code_at = address[7:0] + {address[10:8], 5'b00001};
    endfunction

    function [7:0] pattern_of(input [11:0] address);    // {0, Code, Pixelzeile}
        pattern_of = address[10:3] ^ {address[2:0], 5'b10110};
    endfunction

    always @(posedge clk) begin
        if (en) begin
            ram_dout  <= code_at(ram_addr);
            char_dout <= pattern_of(char_addr);
        end
    end

    // --- Erwartung: Position und Steuersignale drei Pixeltakte verzögert ----
    reg [11:0] x_d [1:3];
    reg [11:0] y_d [1:3];
    reg [2:0]  s_d [1:3];       // {de, hsync, vsync}
    reg [3:0]  valid = 4'b0000;

    always @(posedge clk) begin
        if (en) begin
            x_d[1] <= x;      y_d[1] <= y;      s_d[1] <= {de, hsync, vsync};
            x_d[2] <= x_d[1]; y_d[2] <= y_d[1]; s_d[2] <= s_d[1];
            x_d[3] <= x_d[2]; y_d[3] <= y_d[2]; s_d[3] <= s_d[2];
            valid  <= {valid[2:0], ~rst};
        end
    end

    function [23:0] expected_rgb(input [11:0] px, input [11:0] py, input visible);
        integer    col, row, line, bit_no;
        reg [15:0] address;
        reg [7:0]  pattern;
        begin
            if (!visible) begin
                expected_rgb = 24'h000000;
            end else if (py < 40 || py >= 440) begin
                expected_rgb = BORDER;
            end else begin
                col     = px / 16;
                row     = (py - 40) / 16;
                line    = ((py - 40) / 2) % 8;
                bit_no  = 7 - (px / 2) % 8;
                address = 16'h0400 + row * 40 + col;
                pattern = pattern_of({1'b0, code_at(address), line[2:0]});
                expected_rgb = pattern[bit_no] ? FG : BG;
            end
        end
    endfunction

    always @(negedge clk) begin
        if (valid[3] && !en) begin      // direkt nach einem Pixeltakt
            checked = checked + 1;
            if ({r, g, b} !== expected_rgb(x_d[3], y_d[3], s_d[3][2])) begin
                if (errors < 20)
                    $display("FAIL: (%0d,%0d) Farbe %h, erwartet %h", x_d[3], y_d[3], {r, g, b},
                             expected_rgb(x_d[3], y_d[3], s_d[3][2]));
                errors = errors + 1;
            end
            if ({de_out, hsync_out, vsync_out} !== s_d[3]) begin
                if (errors < 20)
                    $display("FAIL: (%0d,%0d) {de,hsync,vsync}=%b, erwartet %b", x_d[3], y_d[3],
                             {de_out, hsync_out, vsync_out}, s_d[3]);
                errors = errors + 1;
            end
        end
        // 4. Adresse im Bildschirmspeicher
        if (!rst && de && y >= 40 && y < 440 && (ram_addr < 16'h0400 || ram_addr > 16'h07E7)) begin
            if (errors < 20) $display("FAIL: (%0d,%0d) Bildschirmadresse %h", x, y, ram_addr);
            errors = errors + 1;
        end
    end

    reg vsync_prev = 1'b0;
    always @(negedge clk) begin
        if (vsync && !vsync_prev) frames = frames + 1;
        vsync_prev = vsync;
    end

    initial begin
        // Nur die ersten Zeilen aufzeichnen, sonst wird die Datei riesig.
        $dumpfile("tb/build/tb_video_text.vcd");
        $dumpvars(0, tb_video_text);
        #200000 $dumpoff;
    end

    initial begin
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // Bis zum Beginn des zweiten vsync: mehr als ein vollständiges Bild.
        wait (frames == 2);

        if (checked < 800 * 525) begin
            $display("FAIL: nur %0d Pixel geprueft", checked);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS: tb_video_text");
        else             $display("FAIL: tb_video_text (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #60_000_000;
        $display("FAIL: tb_video_text Timeout");
        $finish;
    end

endmodule

`default_nettype wire
