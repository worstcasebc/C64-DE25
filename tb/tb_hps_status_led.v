// tb_hps_status_led — selbstprüfende Testbench für hps_status_led.
//
// Mit kurzen Zeiten: schnelles Blinken alle 4 Takte, langsames alle 16,
// Frist 100 Takte. Geprüft wird:
//   1. Nach dem Reset: kein Lebenszeichen, die LED blinkt schnell, aux aus.
//   2. Lebenszeichen ohne Problem: LED leuchtet dauernd; aux folgt Bit 1.
//   3. Lebenszeichen mit Problem: LED blinkt langsam.
//   4. Kommen die Lebenszeichen rechtzeitig, bleibt es dabei — auch über
//      ein Vielfaches der Frist.
//   5. Bleiben sie aus, gilt der Dienst nach der Frist als weg: schnelles
//      Blinken, aux aus. Vor Ablauf der Frist noch nicht.
//   6. Ein neues Lebenszeichen holt ihn zurück.

`timescale 1ns / 1ps
`default_nettype none

module tb_hps_status_led;

    localparam FAST_HALF = 4;
    localparam SLOW_HALF = 16;
    localparam TIMEOUT   = 100;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        wr = 1'b0;
    reg  [1:0] wr_data = 2'b00;
    wire       alive;
    wire       led;
    wire       aux;

    integer errors = 0;
    integer i;

    hps_status_led #(.FAST_HALF(FAST_HALF), .SLOW_HALF(SLOW_HALF), .TIMEOUT(TIMEOUT)) dut (
        .clk     (clk),
        .rst     (rst),
        .wr      (wr),
        .wr_data (wr_data),
        .alive_q (alive),
        .led_q   (led),
        .aux_q   (aux)
    );

    always #5 clk = ~clk;

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    task sign_of_life(input [1:0] value);
        begin
            @(negedge clk);
            wr_data = value;
            wr      = 1'b1;
            @(negedge clk);
            wr      = 1'b0;
        end
    endtask

    // Beobachtet die LED n Takte lang: Zahl der Wechsel und der Takte, in
    // denen sie an war.
    integer n_toggle, n_on;
    reg     led_old;

    task watch(input integer n);
        integer k;
        begin
            n_toggle = 0;
            n_on     = 0;
            led_old  = led;
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk);
                if (led !== led_old) n_toggle = n_toggle + 1;
                if (led) n_on = n_on + 1;
                led_old = led;
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_hps_status_led.vcd");
        $dumpvars(0, tb_hps_status_led);

        repeat (4) @(negedge clk);
        rst = 1'b0;

        // 1. nach dem Reset: schnell blinken (Wechsel alle 4 Takte)
        repeat (4) @(negedge clk);
        watch(64);
        expect_eq(alive, 0, "1. kein Lebenszeichen");
        expect_eq(n_toggle, 16, "1. schnelles Blinken");
        expect_eq(n_on, 32, "1. halb an, halb aus");
        expect_eq(aux, 0, "1. aux aus");

        // 2. Lebenszeichen ohne Problem, aux gesetzt
        sign_of_life(2'b10);
        repeat (2) @(negedge clk);
        watch(64);
        expect_eq(alive, 1, "2. Dienst lebt");
        expect_eq(n_toggle, 0, "2. LED leuchtet dauernd");
        expect_eq(n_on, 64, "2. LED an");
        expect_eq(aux, 1, "2. aux an");

        // 3. Lebenszeichen mit Problem: langsam blinken (alle 16 Takte)
        sign_of_life(2'b01);
        repeat (2) @(negedge clk);
        watch(64);
        expect_eq(n_toggle, 4, "3. langsames Blinken");
        expect_eq(aux, 0, "3. aux aus");

        // 4. rechtzeitige Lebenszeichen über das Fünffache der Frist
        for (i = 0; i < 10; i = i + 1) begin
            sign_of_life(2'b00);
            repeat (TIMEOUT / 2) @(negedge clk);
            expect_eq(alive, 1, "4. lebt weiter");
        end
        watch(32);
        expect_eq(n_toggle, 0, "4. LED leuchtet dauernd");

        // 5. keine Lebenszeichen mehr
        sign_of_life(2'b10);
        repeat (TIMEOUT - 10) @(negedge clk);
        expect_eq(alive, 1, "5. vor Ablauf der Frist");
        expect_eq(aux, 1, "5. aux noch an");
        repeat (20) @(negedge clk);
        expect_eq(alive, 0, "5. nach Ablauf der Frist");
        expect_eq(aux, 0, "5. aux aus");
        watch(64);
        expect_eq(n_toggle, 16, "5. wieder schnelles Blinken");

        // 6. zurück
        sign_of_life(2'b00);
        repeat (2) @(negedge clk);
        watch(32);
        expect_eq(alive, 1, "6. lebt wieder");
        expect_eq(n_toggle, 0, "6. LED leuchtet");

        if (errors == 0) $display("PASS: tb_hps_status_led");
        else             $display("FAIL: tb_hps_status_led (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
