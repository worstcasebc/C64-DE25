// tb_key_matrix — selbstprüfende Testbench für key_matrix.
//
// 1. Keine Taste: Port B liest immer $FF.
// 2. Jede der 64 Tasten einzeln: Nur wenn ihre Port-A-Leitung auf 0 liegt,
//    erscheint genau ihre Port-B-Leitung als 0.
// 3. Alle Port-A-Leitungen auf 0 (so prüft das KERNAL, ob überhaupt eine
//    Taste gedrückt ist): die Taste ist sichtbar.
// 4. Zwei Tasten gleichzeitig (SHIFT + Buchstabe) an verschiedenen Leitungen.

`timescale 1ns / 1ps
`default_nettype none

module tb_key_matrix;

    reg  [63:0] keys = 64'd0;
    reg  [7:0]  pa   = 8'hFF;
    wire [7:0]  pb;

    integer errors = 0;
    integer n, a;

    key_matrix dut (
        .keys (keys),
        .pa   (pa),
        .pb   (pb)
    );

    task check(input [7:0] port_a, input [7:0] want, input [255:0] what);
        begin
            pa = port_a;
            #1;
            if (pb !== want) begin
                $display("FAIL: %0s: keys=%h pa=%b pb=%b, erwartet %b", what, keys, port_a, pb, want);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // 1. keine Taste
        check(8'h00, 8'hFF, "keine Taste, alle Leitungen 0");
        check(8'hFE, 8'hFF, "keine Taste, eine Leitung 0");

        // 2. und 3. jede Taste einzeln
        for (n = 0; n < 64; n = n + 1) begin
            keys = 64'd1 << n;
            for (a = 0; a < 8; a = a + 1)
                check(~(8'd1 << a), (a == n / 8) ? ~(8'd1 << (n % 8)) : 8'hFF, "einzelne Taste");
            check(8'h00, ~(8'd1 << (n % 8)), "einzelne Taste, alle Leitungen 0");
            check(8'hFF, 8'hFF, "einzelne Taste, keine Leitung 0");
        end

        // 4. LSHIFT (15: PA1/PB7) + A (10: PA1/PB2) + Q (62: PA7/PB6)
        keys = (64'd1 << 15) | (64'd1 << 10) | (64'd1 << 62);
        check(8'b1111_1101, 8'b0111_1011, "SHIFT+A an PA1");
        check(8'b0111_1111, 8'b1011_1111, "Q an PA7");
        check(8'b0111_1101, 8'b0011_1011, "PA1 und PA7");
        check(8'b1111_1011, 8'hFF,        "andere Leitung");

        if (errors == 0) $display("PASS: tb_key_matrix");
        else             $display("FAIL: tb_key_matrix (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
