// tb_hps_byte_port — selbstprüfende Testbench für hps_byte_port.
//
// Zwei Takte ohne festes Verhältnis: clk_av 100 MHz, clk 31,5 MHz. Die Tasks
// av_write/av_read spielen die Brücke, send_byte spielt das Programm unter
// Linux (STATUS abfragen, bis frei, dann DATA schreiben). Geprüft wird:
//   1. Nach dem Reset ist der Port frei und liefert kein Byte.
//   2. Ein Byte: sofort belegt, wartet auf ready, kommt genau einmal an,
//      danach wieder frei.
//   3. Schreiben, solange belegt, wird ignoriert.
//   4. Schreiben ohne Byte 0 (byteenable) oder auf STATUS löst nichts aus.
//   5. 300 Bytes bei zufälligem ready: alle, in der Reihenfolge, keins doppelt.
//   6. Reset des C64 mit wartendem Byte: Byte weg, Port frei, danach normal.
//   7. readdatavalid genau einen Takt nach read; waitrequest nie 1.
//   8. Nach dem Reset sind alle Tasten losgelassen.
//   9. KEYS_LO und KEYS_HI: Der Zustand erscheint beim C64, Rücklesen stimmt,
//      das jeweils andere Wort bleibt.
//  10. Schreiben mit einzelnen Bytes (byteenable) ändert nur diese.
//  11. Die Tastenregister liefern kein Byte im Datenstrom; ein Reset des C64
//      lässt die Tasten stehen.
//  12. RESTORE (STATUS Bit 1): erscheint beim C64, liest sich zurück, lässt
//      Bit 0 und den Datenstrom in Ruhe.
//  13. Joysticks (STATUS Bit 12..8 und 20..16): erscheinen beim C64, lesen
//      sich zurück; jedes Byte von STATUS lässt sich einzeln schreiben.
//  14. Reset-Wunsch (STATUS Bit 2): erscheint beim C64 und bleibt auch dann
//      stehen, wenn dieses Modul selbst im Reset ist.

`timescale 1ns / 1ps
`default_nettype none

module tb_hps_byte_port;

    localparam [1:0] DATA    = 2'd0;
    localparam [1:0] STATUS  = 2'd1;
    localparam [1:0] KEYS_LO = 2'd2;
    localparam [1:0] KEYS_HI = 2'd3;
    localparam N_RAND = 300;

    reg         clk_av = 1'b0;
    reg         rst_av = 1'b1;
    reg  [1:0]  av_address = 2'd0;
    reg         av_write_r = 1'b0;
    reg  [31:0] av_writedata = 32'd0;
    reg  [3:0]  av_byteenable = 4'b0000;
    reg         av_read_r = 1'b0;
    wire [31:0] av_readdata;
    wire        av_readdatavalid;
    wire        av_waitrequest;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    wire [7:0]  data;
    wire        valid;
    reg         ready = 1'b0;
    wire [63:0] keys;
    wire        restore;
    wire [4:0]  joy1, joy2;
    wire        c64_reset;
    reg         rand_ready = 1'b0;

    integer     errors = 0;
    integer     n_got  = 0;
    integer     i;
    reg [7:0]   got  [0:1023];
    reg [7:0]   sent [0:N_RAND-1];
    reg [31:0]  rd;

    hps_byte_port dut (
        .clk_av            (clk_av),
        .rst_av            (rst_av),
        .avs_address       (av_address),
        .avs_write         (av_write_r),
        .avs_writedata     (av_writedata),
        .avs_byteenable    (av_byteenable),
        .avs_read          (av_read_r),
        .avs_readdata      (av_readdata),
        .avs_readdatavalid (av_readdatavalid),
        .avs_waitrequest   (av_waitrequest),
        .clk               (clk),
        .rst               (rst),
        .data_q            (data),
        .valid_q           (valid),
        .ready             (ready),
        .keys_q            (keys),
        .restore_q         (restore),
        .joy1_q            (joy1),
        .joy2_q            (joy2),
        .reset_q           (c64_reset)
    );

    always #5      clk_av = ~clk_av;   // 100 MHz
    always #15.873 clk    = ~clk;      // 31,5 MHz

    // Abnehmer: zählt jedes übergebene Byte.
    always @(posedge clk) begin
        if (!rst && valid && ready) begin
            got[n_got] = data;
            n_got      = n_got + 1;
        end
    end

    always @(negedge clk) begin
        if (rand_ready) ready = $random;
    end

    always @(posedge clk_av) begin
        if (av_waitrequest !== 1'b0) begin
            $display("FAIL: waitrequest ist nicht 0 bei t=%0t", $time);
            errors = errors + 1;
        end
    end

    task expect_eq(input integer got_v, input integer want, input [255:0] what);
        begin
            if (got_v !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got_v, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    task av_write(input [1:0] addr, input [31:0] value, input [3:0] be);
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

    // Liest ein Register und prüft dabei den Zeitpunkt von readdatavalid.
    task av_read(input [1:0] addr, output [31:0] value);
        begin
            @(negedge clk_av);
            av_address = addr;
            av_read_r  = 1'b1;
            @(negedge clk_av);
            av_read_r  = 1'b0;
            expect_eq(av_readdatavalid, 1, "readdatavalid einen Takt nach read");
            value = av_readdata;
            @(negedge clk_av);
            expect_eq(av_readdatavalid, 0, "readdatavalid nur einen Takt lang");
        end
    endtask

    // Wie das Programm unter Linux: warten, bis frei, dann schreiben.
    task send_byte(input [7:0] value);
        integer tries;
        reg [31:0] st;
        begin
            tries = 0;
            av_read(STATUS, st);
            while (st[0] && tries < 1000) begin
                av_read(STATUS, st);
                tries = tries + 1;
            end
            expect_eq(st[0], 0, "Port wird wieder frei");
            av_write(DATA, {24'd0, value}, 4'b1111);
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_hps_byte_port.vcd");
        $dumpvars(0, tb_hps_byte_port);

        repeat (6) @(posedge clk);
        @(negedge clk_av) rst_av = 1'b0;
        @(negedge clk)    rst    = 1'b0;
        repeat (4) @(posedge clk);

        // 1. nach dem Reset
        av_read(STATUS, rd);
        expect_eq(rd, 0, "STATUS nach Reset");
        expect_eq(valid, 0, "valid nach Reset");
        expect_eq(keys === 64'd0, 1, "8. Tasten nach Reset");

        // 2. ein Byte, Abnehmer zunächst nicht bereit
        av_write(DATA, 32'h0000_0041, 4'b1111);
        av_read(STATUS, rd);
        expect_eq(rd, 1, "belegt direkt nach dem Schreiben");
        repeat (10) @(negedge clk);
        expect_eq(valid, 1, "valid wartet auf ready");
        expect_eq(data, 8'h41, "Byte liegt an");
        expect_eq(n_got, 0, "noch nichts uebergeben");
        av_read(STATUS, rd);
        expect_eq(rd, 1, "belegt, solange das Byte wartet");
        ready = 1'b1;
        repeat (6) @(negedge clk);
        expect_eq(n_got, 1, "ein Byte uebergeben");
        expect_eq(got[0], 8'h41, "erstes Byte");
        expect_eq(valid, 0, "valid nach der Uebergabe");
        av_read(STATUS, rd);
        expect_eq(rd, 0, "frei nach der Uebergabe");

        // 3. Schreiben, solange belegt
        ready = 1'b0;
        av_write(DATA, 32'h0000_0011, 4'b1111);
        av_write(DATA, 32'h0000_0022, 4'b1111);
        repeat (10) @(negedge clk);
        ready = 1'b1;
        repeat (10) @(negedge clk);
        expect_eq(n_got, 2, "zweites Schreiben ignoriert");
        expect_eq(got[1], 8'h11, "Byte vor dem ignorierten");

        // 4. ohne Byte 0 und auf STATUS
        av_write(DATA,   32'h3333_3333, 4'b1110);
        av_write(STATUS, 32'h0000_0040, 4'b1111);   // Bit ohne Bedeutung
        av_read(STATUS, rd);
        expect_eq(rd, 0, "frei nach wirkungslosem Schreiben");
        repeat (10) @(negedge clk);
        expect_eq(n_got, 2, "wirkungsloses Schreiben liefert kein Byte");
        av_read(DATA, rd);
        expect_eq(rd, 32'h0000_0011, "DATA liest das letzte Byte");

        // 5. viele Bytes bei zufälligem ready
        rand_ready = 1'b1;
        for (i = 0; i < N_RAND; i = i + 1) begin
            sent[i] = $random;
            send_byte(sent[i]);
        end
        av_read(STATUS, rd);
        while (rd[0]) av_read(STATUS, rd);
        expect_eq(n_got, 2 + N_RAND, "Anzahl nach Zufallstest");
        for (i = 0; i < N_RAND; i = i + 1) begin
            if (got[2 + i] !== sent[i]) begin
                $display("FAIL: Byte %0d: %02x, erwartet %02x", i, got[2 + i], sent[i]);
                errors = errors + 1;
            end
        end

        // 6. Reset des C64 mit wartendem Byte
        rand_ready = 1'b0;
        @(negedge clk) ready = 1'b0;
        av_write(DATA, 32'h0000_0055, 4'b1111);
        repeat (10) @(negedge clk);
        expect_eq(valid, 1, "Byte wartet vor dem Reset");
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        expect_eq(valid, 0, "valid nach Reset des C64");
        repeat (4) @(negedge clk);
        av_read(STATUS, rd);
        expect_eq(rd, 0, "frei nach Reset des C64");
        ready = 1'b1;
        repeat (10) @(negedge clk);
        expect_eq(n_got, 2 + N_RAND, "verworfenes Byte kommt nicht an");
        send_byte(8'h66);
        repeat (10) @(negedge clk);
        expect_eq(n_got, 3 + N_RAND, "Byte nach dem Reset");
        expect_eq(got[2 + N_RAND], 8'h66, "Wert nach dem Reset");

        // 9. Tastenzustand schreiben und zurücklesen
        av_write(KEYS_LO, 32'h8000_0001, 4'b1111);
        repeat (4) @(negedge clk);
        expect_eq(keys === 64'h0000_0000_8000_0001, 1, "9. KEYS_LO beim C64");
        av_write(KEYS_HI, 32'hA000_0005, 4'b1111);
        repeat (4) @(negedge clk);
        expect_eq(keys === 64'hA000_0005_8000_0001, 1, "9. KEYS_HI beim C64");
        av_read(KEYS_LO, rd);
        expect_eq(rd === 32'h8000_0001, 1, "9. KEYS_LO zuruecklesen");
        av_read(KEYS_HI, rd);
        expect_eq(rd === 32'hA000_0005, 1, "9. KEYS_HI zuruecklesen");

        // 10. nur einzelne Bytes
        av_write(KEYS_LO, 32'hFFFF_FFFF, 4'b0100);
        av_write(KEYS_HI, 32'h0000_0000, 4'b1000);
        repeat (4) @(negedge clk);
        expect_eq(keys === 64'h0000_0005_80FF_0001, 1, "10. einzelne Bytes");

        // 11. kein Byte im Datenstrom, Reset des C64 laesst die Tasten stehen
        repeat (6) @(negedge clk);
        expect_eq(n_got, 3 + N_RAND, "11. Tasten liefern kein Byte");
        av_read(STATUS, rd);
        expect_eq(rd, 0, "11. frei nach Tastenschreiben");
        rst = 1'b1;
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (4) @(negedge clk);
        expect_eq(keys === 64'h0000_0005_80FF_0001, 1, "11. Tasten nach Reset des C64");

        // 12. RESTORE
        expect_eq(restore, 0, "12. RESTORE anfangs los");
        av_write(STATUS, 32'h0000_0002, 4'b1111);
        repeat (4) @(negedge clk);
        expect_eq(restore, 1, "12. RESTORE gedrueckt");
        av_read(STATUS, rd);
        expect_eq(rd, 2, "12. STATUS mit RESTORE, nicht belegt");
        av_write(STATUS, 32'h0000_0000, 4'b1110);
        repeat (4) @(negedge clk);
        expect_eq(restore, 1, "12. Schreiben ohne Byte 0 aendert RESTORE nicht");
        av_write(STATUS, 32'h0000_0000, 4'b1111);
        repeat (4) @(negedge clk);
        expect_eq(restore, 0, "12. RESTORE losgelassen");
        expect_eq(n_got, 3 + N_RAND, "12. RESTORE liefert kein Byte");
        expect_eq(keys === 64'h0000_0005_80FF_0001, 1, "12. RESTORE laesst die Tasten stehen");

        // 13. Joysticks
        expect_eq({joy2, joy1}, 0, "13. Joysticks anfangs in Ruhe");
        av_write(STATUS, 32'h0015_0A00, 4'b1111);
        repeat (4) @(negedge clk);
        expect_eq(joy1, 5'h0A, "13. Joystick an Port 1");
        expect_eq(joy2, 5'h15, "13. Joystick an Port 2");
        expect_eq(restore, 0, "13. RESTORE bleibt los");
        av_read(STATUS, rd);
        expect_eq(rd, 32'h0015_0A00, "13. STATUS zuruecklesen");
        av_write(STATUS, 32'hFFFF_FFFF, 4'b0001);      // nur Byte 0: RESTORE
        repeat (4) @(negedge clk);
        expect_eq(restore, 1, "13. RESTORE ueber Byte 0");
        expect_eq(joy1, 5'h0A, "13. Port 1 unveraendert");
        expect_eq(joy2, 5'h15, "13. Port 2 unveraendert");
        av_write(STATUS, 32'h0000_1F00, 4'b0010);      // nur Byte 1: Port 1
        repeat (4) @(negedge clk);
        expect_eq(joy1, 5'h1F, "13. Port 1 ueber Byte 1");
        expect_eq(joy2, 5'h15, "13. Port 2 weiter unveraendert");
        expect_eq(restore, 1, "13. RESTORE weiter gedrueckt");
        av_write(STATUS, 32'h0000_0000, 4'b1111);
        repeat (4) @(negedge clk);
        expect_eq({joy2, joy1, restore}, 0, "13. alles losgelassen");
        expect_eq(n_got, 3 + N_RAND, "13. Joysticks liefern kein Byte");

        // 14. Reset-Wunsch von Linux
        expect_eq(c64_reset, 0, "14. kein Reset-Wunsch anfangs");
        av_write(STATUS, 32'h0000_0004, 4'b1111);
        repeat (4) @(negedge clk);
        expect_eq(c64_reset, 1, "14. Reset-Wunsch");
        expect_eq(restore, 0, "14. RESTORE unberuehrt");
        av_read(STATUS, rd);
        expect_eq(rd, 4, "14. STATUS zuruecklesen");
        rst = 1'b1;                     // im Top-Level folgt daraus der Reset
        repeat (6) @(negedge clk);
        expect_eq(c64_reset, 1, "14. Wunsch bleibt im Reset stehen");
        av_write(STATUS, 32'h0000_0000, 4'b1111);
        repeat (4) @(negedge clk);
        expect_eq(c64_reset, 0, "14. Wunsch zurueckgenommen");
        rst = 1'b0;
        repeat (4) @(negedge clk);

        if (errors == 0) $display("PASS: tb_hps_byte_port");
        else             $display("FAIL: tb_hps_byte_port (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
