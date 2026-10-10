// tb_blink — selbstprüfende Testbench für blink.
//
// Prüft mit kleinem HALF_PERIOD (5 statt 25 Mio.), damit die Simulation
// Sekundenbruchteile dauert:
//   1. Reset hält den Ausgang auf 0.
//   2. Der Ausgang schaltet exakt alle HALF_PERIOD Takte um.
//   3. Ein Reset mitten im Betrieb setzt Ausgang und Zähler zurück.

`timescale 1ns / 1ps
`default_nettype none

module tb_blink;

    localparam HALF_PERIOD = 5;

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    wire led;

    integer errors = 0;
    integer i;

    blink #(.HALF_PERIOD(HALF_PERIOD)) dut (
        .clk   (clk),
        .rst   (rst),
        .led_q (led)
    );

    always #10 clk = ~clk;   // 50 MHz

    task check(input expected, input [255:0] what);
        begin
            if (led !== expected) begin
                $display("FAIL: %0s (led=%b, erwartet %b) bei t=%0t", what, led, expected, $time);
                errors = errors + 1;
            end
        end
    endtask

    // Wartet n Takte und tastet kurz nach der Flanke ab.
    task wait_clk(input integer n);
        begin
            repeat (n) @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_blink.vcd");
        $dumpvars(0, tb_blink);

        // 1. Reset
        wait_clk(3);
        check(1'b0, "Reset haelt LED aus");
        @(negedge clk) rst = 1'b0;

        // 2. Vier Halbperioden: direkt vor dem Umschalten alt, danach neu.
        for (i = 0; i < 4; i = i + 1) begin
            wait_clk(HALF_PERIOD - 1);
            check(i[0], "LED stabil vor Umschaltpunkt");
            wait_clk(1);
            check(~i[0], "LED schaltet nach HALF_PERIOD Takten um");
        end

        // 3. Reset mitten in der Periode (LED ist hier 0 -> erst auf 1 bringen).
        wait_clk(HALF_PERIOD);
        check(1'b1, "LED an vor zweitem Reset");
        wait_clk(2);
        @(negedge clk) rst = 1'b1;
        wait_clk(1);
        check(1'b0, "Reset im Betrieb loescht LED");
        @(negedge clk) rst = 1'b0;
        wait_clk(HALF_PERIOD - 1);
        check(1'b0, "Zaehler startet nach Reset bei 0");
        wait_clk(1);
        check(1'b1, "volle Halbperiode nach Reset");

        if (errors == 0) $display("PASS: tb_blink");
        else             $display("FAIL: tb_blink (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
