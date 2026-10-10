// tb_addr_decode — selbstprüfende Testbench für addr_decode.
//
// Prüft die Grenzen jedes Bereichs (erste/letzte Adresse und die Nachbarn)
// und über alle 65536 Adressen, dass nie zwei Bereiche gleichzeitig aktiv sind.

`timescale 1ns / 1ps
`default_nettype none

module tb_addr_decode;

    reg  [15:0] addr = 16'h0000;
    wire        sel_ram;
    wire        sel_uart;
    wire        sel_rom;

    integer errors = 0;
    integer a;

    addr_decode dut (
        .addr     (addr),
        .sel_ram  (sel_ram),
        .sel_uart (sel_uart),
        .sel_rom  (sel_rom)
    );

    // expected = {ram, uart, rom}
    task check(input [15:0] address, input [2:0] expected);
        begin
            addr = address;
            #1;
            if ({sel_ram, sel_uart, sel_rom} !== expected) begin
                $display("FAIL: addr=%h {ram,uart,rom}=%b, erwartet %b",
                         address, {sel_ram, sel_uart, sel_rom}, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        check(16'h0000, 3'b100);   // RAM-Anfang
        check(16'h01FF, 3'b100);   // Stack
        check(16'h7FFF, 3'b100);   // RAM-Ende
        check(16'h8000, 3'b000);   // direkt dahinter: unbelegt
        check(16'hDDFF, 3'b000);
        check(16'hDE00, 3'b010);   // UART-Anfang
        check(16'hDEFF, 3'b010);   // UART-Ende
        check(16'hDF00, 3'b000);
        check(16'hDFFF, 3'b000);
        check(16'hE000, 3'b001);   // ROM-Anfang
        check(16'hFFFC, 3'b001);   // Reset-Vektor
        check(16'hFFFF, 3'b001);   // ROM-Ende

        for (a = 0; a < 65536; a = a + 1) begin
            addr = a[15:0];
            #1;
            if (sel_ram + sel_uart + sel_rom > 1) begin
                $display("FAIL: addr=%h waehlt mehrere Bereiche", addr);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("PASS: tb_addr_decode");
        else             $display("FAIL: tb_addr_decode (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
