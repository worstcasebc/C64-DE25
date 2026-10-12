// tb_ce_fraction — selbstprüfende Testbench für ce_fraction.
//
// Geprüft wird an drei Verhältnissen (32/63 wie beim Laufwerk, 1/4, 1/1):
//   1. Im Reset kommt keine Freigabe.
//   2. In jedem Fenster von 10 x DEN Takten kommen genau 10 x NUM Freigaben —
//      auch wenn das Fenster irgendwo beginnt.
//   3. Die Freigaben sind gleichmäßig verteilt: Der Abstand zwischen zweien
//      ist DEN / NUM, ab- oder aufgerundet.

`timescale 1ns / 1ps
`default_nettype none

module tb_ce_fraction;

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    wire ce_a, ce_b, ce_c;

    integer errors = 0;

    ce_fraction #(.NUM(32), .DEN(63)) dut_a (.clk(clk), .rst(rst), .ce_q(ce_a));
    ce_fraction #(.NUM(1),  .DEN(4))  dut_b (.clk(clk), .rst(rst), .ce_q(ce_b));
    ce_fraction #(.NUM(1),  .DEN(1))  dut_c (.clk(clk), .rst(rst), .ce_q(ce_c));

    always #10 clk = ~clk;

    integer n_a = 0, n_b = 0, n_c = 0;      // Freigaben im Fenster
    integer gap_a = 0, gap_b = 0;           // Takte seit der letzten Freigabe
    reg     seen_a = 1'b0, seen_b = 1'b0;

    always @(negedge clk) begin
        if (ce_a) n_a = n_a + 1;
        if (ce_b) n_b = n_b + 1;
        if (ce_c) n_c = n_c + 1;

        // Abstände: bei 32/63 sind es 1 oder 2 Takte, bei 1/4 genau 4.
        gap_a = gap_a + 1;
        if (ce_a) begin
            if (seen_a && gap_a != 1 && gap_a != 2) begin
                $display("FAIL: Abstand %0d bei 32/63, t=%0t", gap_a, $time);
                errors = errors + 1;
            end
            seen_a = 1'b1;
            gap_a  = 0;
        end
        gap_b = gap_b + 1;
        if (ce_b) begin
            if (seen_b && gap_b != 4) begin
                $display("FAIL: Abstand %0d bei 1/4, t=%0t", gap_b, $time);
                errors = errors + 1;
            end
            seen_b = 1'b1;
            gap_b  = 0;
        end
    end

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    integer k;

    initial begin
        $dumpfile("tb/build/tb_ce_fraction.vcd");
        $dumpvars(0, tb_ce_fraction);

        // 1. im Reset
        repeat (20) @(negedge clk);
        expect_eq(n_a + n_b + n_c, 0, "Freigaben im Reset");
        rst = 1'b0;

        // 2. Fenster an drei verschiedenen Stellen
        for (k = 0; k < 3; k = k + 1) begin
            repeat (7 + 11 * k) @(negedge clk);
            n_a = 0;
            repeat (630) @(negedge clk);
            expect_eq(n_a, 320, "Freigaben bei 32/63 in 630 Takten");
            n_b = 0;
            repeat (40) @(negedge clk);
            expect_eq(n_b, 10, "Freigaben bei 1/4 in 40 Takten");
            n_c = 0;
            repeat (10) @(negedge clk);
            expect_eq(n_c, 10, "Freigaben bei 1/1 in 10 Takten");
        end

        if (errors == 0) $display("PASS: tb_ce_fraction");
        else             $display("FAIL: tb_ce_fraction (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
