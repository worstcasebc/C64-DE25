// tb_mem_dp_sync — selbstprüfende Testbench für ram_dp_sync und rom_dp_sync.
//
// RAM: 1. Inhalt beim Start ist 0.
//      2. Über A geschriebene Werte liest B an einer anderen Adresse als A.
//      3. Schreiben über A und Lesen derselben Zelle über B im selben Takt
//         liefert den alten Inhalt, einen Takt später den neuen.
//      4. Bei b_en = 0 bleibt der Ausgang von B stehen; A arbeitet weiter.
//      6. Schreiben über A bei a_en = 0: Die Zelle ändert sich, der
//         Leseausgang von A nicht.
// ROM: 5. Beide Anschlüsse lesen unabhängig (Inhalt: tb/data/rom_test.hex).

`timescale 1ns / 1ps
`default_nettype none

module tb_mem_dp_sync;

    reg        clk    = 1'b0;
    reg        a_en   = 1'b0;
    reg        a_we   = 1'b0;
    reg  [3:0] a_addr = 4'h0;
    reg  [7:0] a_din  = 8'h00;
    reg        b_en   = 1'b0;
    reg  [3:0] b_addr = 4'h0;
    wire [7:0] ram_a;
    wire [7:0] ram_b;
    wire [7:0] rom_a;
    wire [7:0] rom_b;

    integer errors = 0;
    integer i;

    ram_dp_sync #(.ADDR_W(4)) dut_ram (
        .clk      (clk),
        .a_en     (a_en),
        .a_we     (a_we),
        .a_addr   (a_addr),
        .a_din    (a_din),
        .a_dout_q (ram_a),
        .b_en     (b_en),
        .b_addr   (b_addr),
        .b_dout_q (ram_b)
    );

    rom_dp_sync #(.ADDR_W(4), .INIT_FILE("tb/data/rom_test.hex")) dut_rom (
        .clk      (clk),
        .a_en     (a_en),
        .a_addr   (a_addr),
        .a_dout_q (rom_a),
        .b_en     (b_en),
        .b_addr   (b_addr),
        .b_dout_q (rom_b)
    );

    always #10 clk = ~clk;

    // Ein Takt mit beiden Anschlüssen: Signale anlegen, eine Flanke abwarten.
    task access(input ena, input write, input [3:0] aa, input [7:0] d,
                input enb, input [3:0] ab);
        begin
            @(negedge clk);
            a_en = ena; a_we = write; a_addr = aa; a_din = d;
            b_en = enb; b_addr = ab;
            @(posedge clk); #1;
        end
    endtask

    task expect_val(input [7:0] got, input [7:0] want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %h, erwartet %h bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_mem_dp_sync.vcd");
        $dumpvars(0, tb_mem_dp_sync);

        // 1. Startinhalt
        access(1'b1, 1'b0, 4'h7, 8'h00, 1'b1, 4'hC);
        expect_val(ram_a, 8'h00, "RAM Startinhalt ueber A");
        expect_val(ram_b, 8'h00, "RAM Startinhalt ueber B");

        // 2. Schreiben über A, lesen über beide an verschiedenen Adressen
        for (i = 0; i < 16; i = i + 1) access(1'b1, 1'b1, i[3:0], 8'hA0 + i[7:0], 1'b0, 4'h0);
        for (i = 0; i < 16; i = i + 1) begin
            access(1'b1, 1'b0, i[3:0], 8'h00, 1'b1, 4'hF - i[3:0]);
            expect_val(ram_a, 8'hA0 + i[7:0], "RAM lesen ueber A");
            expect_val(ram_b, 8'hAF - i[7:0], "RAM lesen ueber B");
        end

        // 3. Schreiben und Lesen derselben Zelle im selben Takt
        access(1'b1, 1'b1, 4'h3, 8'h77, 1'b1, 4'h3);
        expect_val(ram_b, 8'hA3, "RAM alter Inhalt ueber B beim Schreiben");
        access(1'b0, 1'b0, 4'h0, 8'h00, 1'b1, 4'h3);
        expect_val(ram_b, 8'h77, "RAM neuer Inhalt ueber B danach");

        // 4. b_en = 0: B bleibt stehen, A liest weiter
        access(1'b1, 1'b0, 4'h5, 8'h00, 1'b0, 4'h9);
        expect_val(ram_b, 8'h77, "RAM-Ausgang B bei b_en=0");
        expect_val(ram_a, 8'hA5, "RAM-Ausgang A bei b_en=0");

        // 5. ROM: Datei enthält 10, 21, 32, ... (Adresse i -> i*0x11 + 0x10)
        for (i = 0; i < 15; i = i + 1) begin
            access(1'b1, 1'b0, i[3:0], 8'h00, 1'b1, 4'hE - i[3:0]);
            expect_val(rom_a, 8'h10 + i[7:0] * 8'h11, "ROM ueber A");
            expect_val(rom_b, 8'hFE - i[7:0] * 8'h11, "ROM ueber B");
        end

        // 6. Schreiben ohne Lesefreigabe (zuletzt über A gelesen: Zelle 5 -> A5)
        access(1'b1, 1'b0, 4'h5, 8'h00, 1'b0, 4'h0);
        access(1'b0, 1'b1, 4'h9, 8'h99, 1'b0, 4'h0);
        expect_val(ram_a, 8'hA5, "RAM-Ausgang A nach Schreiben ohne a_en");
        access(1'b1, 1'b0, 4'h9, 8'h00, 1'b0, 4'h0);
        expect_val(ram_a, 8'h99, "RAM-Inhalt nach Schreiben ohne a_en");

        if (errors == 0) $display("PASS: tb_mem_dp_sync");
        else             $display("FAIL: tb_mem_dp_sync (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
