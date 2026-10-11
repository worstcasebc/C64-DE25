// tb_ascii_key_typer — selbstprüfende Testbench für ascii_key_typer.
//
// Die Zeichen kommen wie im Top-Level aus einer Warteschlange (fifo_sync).
// Mit PRESS_CLKS = 6 und RELEASE_CLKS = 4:
// 1. Ein Zeichen drückt genau seine Taste für 6 Takte, danach 4 Takte Pause;
//    busy ist währenddessen 1.
// 2. Stichproben der Übersetzung: Groß-/Kleinbuchstaben, Ziffern, Zeichen
//    mit SHIFT, Enter, Rücktaste, Esc, Steuercodes für Cursor/HOME/F-Tasten.
// 3. Unbekannte Zeichen werden ignoriert.
// 4. Eine ganze Zeile auf einmal (so schickt sie ein Terminal im
//    Zeilenmodus): alle Zeichen werden nacheinander getippt, keines fehlt.
// 5. Zeilenende: CR, LF und CR+LF ergeben jeweils genau ein RETURN.

`timescale 1ns / 1ps
`default_nettype none

module tb_ascii_key_typer;

    localparam PRESS = 6, RELEASE = 4;
    localparam [63:0] SHIFT = 64'd1 << 15, RETURN = 64'd1 << 1;

    reg         clk   = 1'b0;
    reg         rst   = 1'b1;
    reg  [7:0]  data  = 8'h00;
    reg         valid = 1'b0;
    wire        fifo_empty;
    wire        fifo_full;
    wire [7:0]  fifo_data;
    wire        fifo_rd;
    wire        busy;
    wire [63:0] keys;

    integer errors = 0;
    integer n;

    fifo_sync #(.ADDR_W(4)) u_fifo (
        .clk    (clk),
        .rst    (rst),
        .wr_en  (valid),
        .din    (data),
        .full   (fifo_full),
        .rd_en  (fifo_rd),
        .dout_q (fifo_data),
        .empty  (fifo_empty)
    );

    ascii_key_typer #(.PRESS_CLKS(PRESS), .RELEASE_CLKS(RELEASE)) dut (
        .clk        (clk),
        .rst        (rst),
        .fifo_empty (fifo_empty),
        .fifo_data  (fifo_data),
        .fifo_rd    (fifo_rd),
        .busy       (busy),
        .keys       (keys)
    );

    always #10 clk = ~clk;

    // --- Protokoll der Tastendrücke: jede neue Tastenkombination einmal -----
    reg [63:0] pressed [0:31];
    integer    n_pressed = 0;
    reg [63:0] keys_prev = 64'd0;

    always @(negedge clk) begin
        if (keys != 64'd0 && keys_prev == 64'd0) begin
            pressed[n_pressed] = keys;
            n_pressed = n_pressed + 1;
        end
        keys_prev = keys;
    end

    task send(input [7:0] ch);          // ein Zeichen in die Warteschlange
        begin
            @(negedge clk);
            data = ch; valid = 1'b1;
            @(negedge clk);
            valid = 1'b0;
        end
    endtask

    task fail(input [255:0] what);
        begin
            $display("FAIL: %0s bei t=%0t", what, $time);
            errors = errors + 1;
        end
    endtask

    task expect_keys(input [63:0] want, input [255:0] what);
        begin
            if (keys !== want) begin
                $display("FAIL: %0s: keys=%h, erwartet %h bei t=%0t", what, keys, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    // Wartet, bis alles getippt ist, und vergleicht das Protokoll.
    task expect_pressed(input integer index, input [63:0] want, input [255:0] what);
        begin
            if (pressed[index] !== want) begin
                $display("FAIL: %0s: Tastendruck %0d ist %h, erwartet %h", what, index, pressed[index], want);
                errors = errors + 1;
            end
        end
    endtask

    // Tippt ein einzelnes Zeichen und prüft, welche Tasten es drückt.
    task check_char(input [7:0] ch, input [63:0] want, input [255:0] what);
        begin
            n_pressed = 0;
            send(ch);
            wait (busy);
            wait (!busy);
            @(negedge clk);
            if (n_pressed != 1) fail(what);
            else expect_pressed(0, want, what);
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_ascii_key_typer.vcd");
        $dumpvars(0, tb_ascii_key_typer);

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        expect_keys(64'd0, "Tasten nach Reset");
        if (busy) fail("busy=1 nach Reset");

        // 1. Zeitverlauf für 'A' (Taste 10)
        send("A");
        wait (keys != 64'd0);
        @(negedge clk);
        for (n = 0; n < PRESS; n = n + 1) begin
            expect_keys(64'd1 << 10, "A gedrueckt");
            if (!busy) fail("busy=0 beim Druecken");
            @(negedge clk);
        end
        for (n = 0; n < RELEASE; n = n + 1) begin
            expect_keys(64'd0, "A losgelassen");
            if (!busy) fail("busy=0 in der Pause");
            @(negedge clk);
        end
        if (busy) fail("busy=1 nach der Pause");

        // 2. Übersetzung
        check_char("a",   64'd1 << 10,           "a");
        check_char("Q",   64'd1 << 62,           "Q");
        check_char("z",   64'd1 << 12,           "z");
        check_char("0",   64'd1 << 35,           "0");
        check_char("1",   64'd1 << 56,           "1");
        check_char("!",   (64'd1 << 56) | SHIFT, "!");
        check_char("\"",  (64'd1 << 59) | SHIFT, "Anfuehrungszeichen");
        check_char("?",   (64'd1 << 55) | SHIFT, "?");
        check_char("(",   (64'd1 << 27) | SHIFT, "(");
        check_char(" ",   64'd1 << 60,           "Leerzeichen");
        check_char(8'h0D, RETURN,                "Enter");
        check_char(8'h08, 64'd1 << 0,            "Ruecktaste");
        check_char(8'h7F, 64'd1 << 0,            "DEL");
        check_char(8'h1B, 64'd1 << 63,           "Esc");
        check_char(8'h03, 64'd1 << 63,           "RUN/STOP");
        check_char(8'h11, 64'd1 << 7,            "Cursor runter");
        check_char(8'h91, (64'd1 << 7) | SHIFT,  "Cursor hoch");
        check_char(8'h1D, 64'd1 << 2,            "Cursor rechts");
        check_char(8'h9D, (64'd1 << 2) | SHIFT,  "Cursor links");
        check_char(8'h13, 64'd1 << 51,           "HOME");
        check_char(8'h93, (64'd1 << 51) | SHIFT, "CLR");
        check_char(8'h94, (64'd1 << 0) | SHIFT,  "INS");
        check_char(8'h85, 64'd1 << 4,            "F1");
        check_char(8'h88, 64'd1 << 3,            "F7");
        check_char(8'h8C, (64'd1 << 3) | SHIFT,  "F8");

        // 3. unbekannte Zeichen
        n_pressed = 0;
        send("~");
        send(8'h01);
        repeat (PRESS + RELEASE + 4) @(negedge clk);
        if (n_pressed != 0) fail("unbekanntes Zeichen wurde getippt");
        if (busy) fail("busy=1 nach unbekannten Zeichen");

        // 4. ganze Zeile auf einmal: PRINT 3+4 und Enter
        n_pressed = 0;
        send("P"); send("R"); send("I"); send("N"); send("T"); send(" ");
        send("3"); send("+"); send("4"); send(8'h0D);
        wait (!busy);
        @(negedge clk);
        if (n_pressed != 10) fail("Zeile: Anzahl der Tastendruecke stimmt nicht");
        expect_pressed(0, 64'd1 << 41, "Zeile: P");
        expect_pressed(1, 64'd1 << 17, "Zeile: R");
        expect_pressed(2, 64'd1 << 33, "Zeile: I");
        expect_pressed(3, 64'd1 << 39, "Zeile: N");
        expect_pressed(4, 64'd1 << 22, "Zeile: T");
        expect_pressed(5, 64'd1 << 60, "Zeile: Leerzeichen");
        expect_pressed(6, 64'd1 << 8,  "Zeile: 3");
        expect_pressed(7, 64'd1 << 40, "Zeile: +");
        expect_pressed(8, 64'd1 << 11, "Zeile: 4");
        expect_pressed(9, RETURN,      "Zeile: Enter");

        // 5. Zeilenende: A CR LF B LF C CR D  ->  A RET B RET C RET D
        n_pressed = 0;
        send("A"); send(8'h0D); send(8'h0A); send("B"); send(8'h0A);
        send("C"); send(8'h0D); send("D");
        wait (!busy);
        @(negedge clk);
        if (n_pressed != 7) fail("Zeilenende: Anzahl der Tastendruecke stimmt nicht");
        expect_pressed(1, RETURN,      "Zeilenende: CR+LF");
        expect_pressed(2, 64'd1 << 28, "Zeilenende: B");
        expect_pressed(3, RETURN,      "Zeilenende: LF allein");
        expect_pressed(5, RETURN,      "Zeilenende: CR allein");
        expect_pressed(6, 64'd1 << 18, "Zeilenende: D");

        if (errors == 0) $display("PASS: tb_ascii_key_typer");
        else             $display("FAIL: tb_ascii_key_typer (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #1_000_000;
        $display("FAIL: tb_ascii_key_typer Timeout");
        $finish;
    end

endmodule

`default_nettype wire
