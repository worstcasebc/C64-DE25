// tb_audio_boxcar — selbstprüfende Testbench für audio_boxcar.
//
// 1. 16 gleiche Werte ergeben genau diesen Wert (positiv und negativ).
// 2. Eine Gruppe aus 8-mal +1000 und 8-mal -1000 ergibt 0; aus 15-mal 0 und
//    einmal 1600 ergibt 100.
// 3. Die größten Werte laufen nicht über.
// 4. Ohne in_valid ändert sich nichts.
// 5. Der Ausgang wechselt nur am Ende einer vollständigen 16er-Gruppe.

`timescale 1ns / 1ps
`default_nettype none

module tb_audio_boxcar;

    reg                clk      = 1'b0;
    reg                rst      = 1'b1;
    reg  signed [17:0] in       = 18'sd0;
    reg                in_valid = 1'b0;
    wire signed [17:0] out;

    integer errors = 0;
    integer i;

    audio_boxcar #(.W(18)) dut (
        .clk      (clk),
        .rst      (rst),
        .in       (in),
        .in_valid (in_valid),
        .out_q    (out)
    );

    always #10 clk = ~clk;

    task feed(input signed [17:0] value);   // ein gültiger Wert, dann eine Lücke
        begin
            @(negedge clk);
            in = value; in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task expect_out(input signed [17:0] want, input [255:0] what);
        begin
            if (out !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, out, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_audio_boxcar.vcd");
        $dumpvars(0, tb_audio_boxcar);

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        expect_out(18'sd0, "Ausgang nach Reset");

        // 1. gleiche Werte; 5. Ausgang wechselt erst nach dem 16. Wert
        for (i = 0; i < 15; i = i + 1) feed(18'sd12345);
        expect_out(18'sd0, "Ausgang nach 15 Werten");
        feed(18'sd12345);
        expect_out(18'sd12345, "Mittel aus 16 gleichen Werten");
        for (i = 0; i < 16; i = i + 1) feed(-18'sd777);
        expect_out(-18'sd777, "Mittel aus 16 gleichen negativen Werten");

        // 2. gemischte Gruppen
        for (i = 0; i < 16; i = i + 1) feed((i < 8) ? 18'sd1000 : -18'sd1000);
        expect_out(18'sd0, "Mittel aus +1000 und -1000");
        for (i = 0; i < 16; i = i + 1) feed((i == 7) ? 18'sd1600 : 18'sd0);
        expect_out(18'sd100, "Mittel mit einem Ausreisser");

        // 3. Grenzwerte
        for (i = 0; i < 16; i = i + 1) feed(18'sd131071);
        expect_out(18'sd131071, "groesster Wert");
        for (i = 0; i < 16; i = i + 1) feed(-18'sd131072);
        expect_out(-18'sd131072, "kleinster Wert");

        // 4. ohne in_valid
        @(negedge clk);
        in = 18'sd5000; in_valid = 1'b0;
        repeat (40) @(negedge clk);
        expect_out(-18'sd131072, "Ausgang ohne in_valid");
        for (i = 0; i < 16; i = i + 1) feed(18'sd16);
        expect_out(18'sd16, "Gruppe nach der Pause unverfaelscht");

        if (errors == 0) $display("PASS: tb_audio_boxcar");
        else             $display("FAIL: tb_audio_boxcar (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
