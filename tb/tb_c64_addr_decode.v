// tb_c64_addr_decode — selbstprüfende Testbench für c64_addr_decode.
//
// 1. Stichproben an den Bereichsgrenzen in der Startkonfiguration ($01 = 7).
// 2. Die acht Banking-Kombinationen für die drei umschaltbaren Bereiche.
// 3. Über alle Adressen und Kombinationen: genau ein Bereich ist aktiv, und
//    außerhalb der umschaltbaren Bereiche antwortet immer das RAM.

`timescale 1ns / 1ps
`default_nettype none

module tb_c64_addr_decode;

    reg  [15:0] addr = 16'h0000;
    reg  [2:0]  bank = 3'b111;      // {charen, hiram, loram} wie Bits 2..0 von $01
    wire        sel_port;
    wire        sel_ram;
    wire        sel_basic;
    wire        sel_char;
    wire        sel_io;
    wire        sel_kernal;

    integer errors = 0;
    integer a;
    integer b;

    localparam [5:0] PORT   = 6'b100000;
    localparam [5:0] RAM    = 6'b010000;
    localparam [5:0] BASIC  = 6'b001000;
    localparam [5:0] CHAR   = 6'b000100;
    localparam [5:0] IO     = 6'b000010;
    localparam [5:0] KERNAL = 6'b000001;

    wire [5:0] sel = {sel_port, sel_ram, sel_basic, sel_char, sel_io, sel_kernal};

    c64_addr_decode dut (
        .addr       (addr),
        .loram      (bank[0]),
        .hiram      (bank[1]),
        .charen     (bank[2]),
        .sel_port   (sel_port),
        .sel_ram    (sel_ram),
        .sel_basic  (sel_basic),
        .sel_char   (sel_char),
        .sel_io     (sel_io),
        .sel_kernal (sel_kernal)
    );

    task check(input [2:0] banking, input [15:0] address, input [5:0] expected);
        begin
            bank = banking;
            addr = address;
            #1;
            if (sel !== expected) begin
                $display("FAIL: bank=%b addr=%h sel=%b, erwartet %b",
                         banking, address, sel, expected);
                errors = errors + 1;
            end
        end
    endtask

    // Erwartung für die drei umschaltbaren Bereiche bei einer Kombination
    task check_bank(input [2:0] banking, input [5:0] a000, input [5:0] d000, input [5:0] e000);
        begin
            check(banking, 16'hA000, a000);
            check(banking, 16'hBFFF, a000);
            check(banking, 16'hD000, d000);
            check(banking, 16'hDFFF, d000);
            check(banking, 16'hE000, e000);
            check(banking, 16'hFFFF, e000);
        end
    endtask

    initial begin
        // 1. Bereichsgrenzen in der Startkonfiguration
        check(3'b111, 16'h0000, PORT);
        check(3'b111, 16'h0001, PORT);
        check(3'b111, 16'h0002, RAM);
        check(3'b111, 16'h9FFF, RAM);
        check(3'b111, 16'hA000, BASIC);
        check(3'b111, 16'hBFFF, BASIC);
        check(3'b111, 16'hC000, RAM);
        check(3'b111, 16'hCFFF, RAM);
        check(3'b111, 16'hD000, IO);
        check(3'b111, 16'hDFFF, IO);
        check(3'b111, 16'hE000, KERNAL);
        check(3'b111, 16'hFFFC, KERNAL);    // Reset-Vektor

        // 2. Alle Kombinationen    {charen,hiram,loram}  $A000  $D000  $E000
        check_bank(3'b111, BASIC, IO,   KERNAL);
        check_bank(3'b110, RAM,   IO,   KERNAL);
        check_bank(3'b101, RAM,   IO,   RAM);
        check_bank(3'b100, RAM,   RAM,  RAM);
        check_bank(3'b011, BASIC, CHAR, KERNAL);
        check_bank(3'b010, RAM,   CHAR, KERNAL);
        check_bank(3'b001, RAM,   CHAR, RAM);
        check_bank(3'b000, RAM,   RAM,  RAM);

        // 3. Genau ein Bereich aktiv; feste Bereiche sind immer RAM bzw. Port
        for (b = 0; b < 8; b = b + 1) begin
            for (a = 0; a < 65536; a = a + 1) begin
                bank = b[2:0];
                addr = a[15:0];
                #1;
                if (sel_port + sel_ram + sel_basic + sel_char + sel_io + sel_kernal != 1) begin
                    $display("FAIL: bank=%b addr=%h sel=%b nicht eindeutig", bank, addr, sel);
                    errors = errors + 1;
                end
                if (a < 2 && sel !== PORT) begin
                    $display("FAIL: bank=%b addr=%h kein CPU-Port", bank, addr);
                    errors = errors + 1;
                end
                if (((a >= 2 && a < 16'hA000) || (a >= 16'hC000 && a < 16'hD000)) && sel !== RAM) begin
                    $display("FAIL: bank=%b addr=%h kein RAM", bank, addr);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) $display("PASS: tb_c64_addr_decode");
        else             $display("FAIL: tb_c64_addr_decode (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
