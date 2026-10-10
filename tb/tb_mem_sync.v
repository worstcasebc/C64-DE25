// tb_mem_sync — selbstprüfende Testbench für ram_sync und rom_sync.
//
// RAM: 1. Geschriebene Werte lassen sich zurücklesen (einen Takt verzögert).
//      2. Bei en = 0 wird weder geschrieben noch der Ausgang verändert.
//      3. Lesen während des Schreibens liefert noch den alten Inhalt.
// ROM: 4. Der Inhalt stammt aus der Hex-Datei (tb/data/rom_test.hex).
//      5. Bei en = 0 bleibt der Ausgang stehen.

`timescale 1ns / 1ps
`default_nettype none

module tb_mem_sync;

    reg        clk = 1'b0;
    reg        en  = 1'b0;
    reg        we  = 1'b0;
    reg  [3:0] addr = 4'h0;
    reg  [7:0] din  = 8'h00;
    wire [7:0] ram_dout;
    wire [7:0] rom_dout;

    integer errors = 0;
    integer i;

    ram_sync #(.ADDR_W(4)) dut_ram (
        .clk    (clk),
        .en     (en),
        .we     (we),
        .addr   (addr),
        .din    (din),
        .dout_q (ram_dout)
    );

    rom_sync #(.ADDR_W(4), .INIT_FILE("tb/data/rom_test.hex")) dut_rom (
        .clk    (clk),
        .en     (en),
        .addr   (addr),
        .dout_q (rom_dout)
    );

    always #10 clk = ~clk;

    // Ein Buszugriff: Signale anlegen, eine Flanke abwarten.
    task access(input enable, input write, input [3:0] a, input [7:0] d);
        begin
            @(negedge clk);
            en = enable; we = write; addr = a; din = d;
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
        $dumpfile("tb/build/tb_mem_sync.vcd");
        $dumpvars(0, tb_mem_sync);

        // 1. Schreiben und zurücklesen
        for (i = 0; i < 16; i = i + 1) access(1'b1, 1'b1, i[3:0], 8'hA0 + i[7:0]);
        for (i = 0; i < 16; i = i + 1) begin
            access(1'b1, 1'b0, i[3:0], 8'h00);
            expect_val(ram_dout, 8'hA0 + i[7:0], "RAM zuruecklesen");
        end

        // 2. en = 0: kein Schreiben, Ausgang bleibt (zuletzt gelesen: Adresse 15)
        access(1'b0, 1'b1, 4'h3, 8'h55);
        expect_val(ram_dout, 8'hAF, "RAM-Ausgang bei en=0");
        access(1'b1, 1'b0, 4'h3, 8'h00);
        expect_val(ram_dout, 8'hA3, "RAM unveraendert nach Schreiben mit en=0");

        // 3. Lesen während des Schreibens liefert den alten Inhalt
        access(1'b1, 1'b1, 4'h3, 8'h77);
        expect_val(ram_dout, 8'hA3, "RAM alter Inhalt beim Schreiben");
        access(1'b1, 1'b0, 4'h3, 8'h00);
        expect_val(ram_dout, 8'h77, "RAM neuer Inhalt danach");

        // 4. ROM-Inhalt: Datei enthält 10, 21, 32, ... (Adresse i -> i*0x11 + 0x10)
        for (i = 0; i < 15; i = i + 1) begin
            access(1'b1, 1'b0, i[3:0], 8'h00);
            expect_val(rom_dout, 8'h10 + i[7:0] * 8'h11, "ROM-Inhalt");
        end

        // 5. ROM bei en = 0 (zuletzt gelesen: Adresse 14 -> FE)
        access(1'b0, 1'b0, 4'h0, 8'h00);
        expect_val(rom_dout, 8'hFE, "ROM-Ausgang bei en=0");

        if (errors == 0) $display("PASS: tb_mem_sync");
        else             $display("FAIL: tb_mem_sync (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
