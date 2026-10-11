// tb_cpu_port — selbstprüfende Testbench für cpu_port.
//
// 1. Nach Reset: alle Leitungen Eingänge, Banking-Leitungen durch Pull-ups 1.
// 2. Datenregister wirkt nicht, solange die Leitung Eingang ist.
// 3. KERNAL-Startwerte (DDR $2F, Daten $37) und Zurücklesen.
// 4. Jede Banking-Leitung lässt sich einzeln auf 0 schalten.
// 5. Schreiben ohne en bzw. ohne sel wird ignoriert.
// 6. Reset stellt den Startzustand wieder her.

`timescale 1ns / 1ps
`default_nettype none

module tb_cpu_port;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        en  = 1'b0;
    reg        sel = 1'b0;
    reg        we  = 1'b0;
    reg        a0  = 1'b0;
    reg  [7:0] din = 8'h00;
    wire [7:0] dout;
    wire       loram;
    wire       hiram;
    wire       charen;

    integer errors = 0;

    cpu_port dut (
        .clk    (clk),
        .rst    (rst),
        .en     (en),
        .sel    (sel),
        .we     (we),
        .a0     (a0),
        .din    (din),
        .dout_q (dout),
        .loram  (loram),
        .hiram  (hiram),
        .charen (charen)
    );

    always #10 clk = ~clk;

    // Ein Buszugriff: Signale anlegen, eine Flanke abwarten.
    task access(input enable, input select, input write, input a, input [7:0] d);
        begin
            @(negedge clk);
            en = enable; sel = select; we = write; a0 = a; din = d;
            @(posedge clk); #1;
        end
    endtask

    task expect_read(input a, input [7:0] want, input [255:0] what);
        begin
            access(1'b1, 1'b1, 1'b0, a, 8'h00);
            if (dout !== want) begin
                $display("FAIL: %0s: %h, erwartet %h bei t=%0t", what, dout, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    // want = {charen, hiram, loram}, also wie die Bits 2..0 von $01
    task expect_lines(input [2:0] want, input [255:0] what);
        begin
            if ({charen, hiram, loram} !== want) begin
                $display("FAIL: %0s: {charen,hiram,loram}=%b, erwartet %b bei t=%0t",
                         what, {charen, hiram, loram}, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_cpu_port.vcd");
        $dumpvars(0, tb_cpu_port);

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 1. Zustand nach Reset
        expect_lines(3'b111, "Leitungen nach Reset");
        expect_read(1'b0, 8'h00, "DDR nach Reset");
        expect_read(1'b1, 8'h17, "Port nach Reset");

        // 2. Datenregister ohne Wirkung, solange alles Eingang ist
        access(1'b1, 1'b1, 1'b1, 1'b1, 8'h00);
        expect_lines(3'b111, "Leitungen als Eingang");
        expect_read(1'b1, 8'h17, "Port als Eingang");

        // 3. KERNAL-Startwerte
        access(1'b1, 1'b1, 1'b1, 1'b1, 8'h37);
        access(1'b1, 1'b1, 1'b1, 1'b0, 8'h2F);
        expect_lines(3'b111, "Leitungen bei $37");
        expect_read(1'b0, 8'h2F, "DDR zuruecklesen");
        expect_read(1'b1, 8'h37, "Port bei $37");

        // 4. Banking-Leitungen einzeln
        access(1'b1, 1'b1, 1'b1, 1'b1, 8'h36);
        expect_lines(3'b110, "LORAM = 0");
        access(1'b1, 1'b1, 1'b1, 1'b1, 8'h35);
        expect_lines(3'b101, "HIRAM = 0");
        access(1'b1, 1'b1, 1'b1, 1'b1, 8'h33);
        expect_lines(3'b011, "CHAREN = 0");
        access(1'b1, 1'b1, 1'b1, 1'b1, 8'h00);
        expect_lines(3'b000, "alles RAM");
        expect_read(1'b1, 8'h10, "Port bei $00: Eingang Bit 4 bleibt 1");

        // 5. Schreiben ohne en bzw. ohne sel
        access(1'b0, 1'b1, 1'b1, 1'b1, 8'h37);
        expect_lines(3'b000, "Schreiben mit en=0");
        access(1'b1, 1'b0, 1'b1, 1'b1, 8'h37);
        expect_lines(3'b000, "Schreiben mit sel=0");

        // 6. Reset
        @(negedge clk) rst = 1'b1;
        @(negedge clk) rst = 1'b0;
        expect_lines(3'b111, "Leitungen nach zweitem Reset");
        expect_read(1'b0, 8'h00, "DDR nach zweitem Reset");

        if (errors == 0) $display("PASS: tb_cpu_port");
        else             $display("FAIL: tb_cpu_port (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
