// tb_fifo_sync — selbstprüfende Testbench für fifo_sync (8 Einträge).
//
// 1. Nach Reset: leer, nicht voll.
// 2. Werte kommen in der Reihenfolge heraus, in der sie hineingingen.
// 3. Voll nach 8 Einträgen; ein weiterer Wert geht verloren, der Inhalt
//    bleibt unbeschädigt.
// 4. Lesen aus der leeren Schlange ändert nichts.
// 5. Gleichzeitig schreiben und lesen, mehrmals im Kreis herum.

`timescale 1ns / 1ps
`default_nettype none

module tb_fifo_sync;

    reg        clk   = 1'b0;
    reg        rst   = 1'b1;
    reg        wr_en = 1'b0;
    reg        rd_en = 1'b0;
    reg  [7:0] din   = 8'h00;
    wire [7:0] dout;
    wire       full;
    wire       empty;

    integer errors = 0;
    integer i;

    fifo_sync #(.ADDR_W(3)) dut (
        .clk    (clk),
        .rst    (rst),
        .wr_en  (wr_en),
        .din    (din),
        .full   (full),
        .rd_en  (rd_en),
        .dout_q (dout),
        .empty  (empty)
    );

    always #10 clk = ~clk;

    // Ein Takt mit den gewünschten Zugriffen.
    task step(input write, input [7:0] value, input read);
        begin
            @(negedge clk);
            wr_en = write; din = value; rd_en = read;
            @(posedge clk); #1;
            wr_en = 1'b0; rd_en = 1'b0;
        end
    endtask

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_fifo_sync.vcd");
        $dumpvars(0, tb_fifo_sync);

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 1. Reset
        expect_eq(empty, 1, "empty nach Reset");
        expect_eq(full, 0, "full nach Reset");

        // 2. Reihenfolge
        for (i = 0; i < 5; i = i + 1) step(1'b1, 8'h10 + i[7:0], 1'b0);
        expect_eq(empty, 0, "empty nach Schreiben");
        for (i = 0; i < 5; i = i + 1) begin
            step(1'b0, 8'h00, 1'b1);
            expect_eq(dout, 8'h10 + i, "Reihenfolge");
        end
        expect_eq(empty, 1, "empty nach Leeren");

        // 3. voll
        for (i = 0; i < 8; i = i + 1) step(1'b1, 8'h20 + i[7:0], 1'b0);
        expect_eq(full, 1, "full nach 8 Eintraegen");
        step(1'b1, 8'hEE, 1'b0);            // geht verloren
        for (i = 0; i < 8; i = i + 1) begin
            step(1'b0, 8'h00, 1'b1);
            expect_eq(dout, 8'h20 + i, "Inhalt nach Ueberlauf");
        end
        expect_eq(empty, 1, "empty nach Ueberlauf-Test");

        // 4. Lesen aus leerer Schlange
        step(1'b0, 8'h00, 1'b1);
        expect_eq(dout, 8'h27, "Ausgang nach Lesen aus leerer Schlange");
        expect_eq(empty, 1, "empty nach Lesen aus leerer Schlange");
        step(1'b1, 8'h55, 1'b0);
        step(1'b0, 8'h00, 1'b1);
        expect_eq(dout, 8'h55, "Wert nach Lesen aus leerer Schlange");

        // 5. gleichzeitig schreiben und lesen: Füllstand bleibt 2
        step(1'b1, 8'h80, 1'b0);
        step(1'b1, 8'h81, 1'b0);
        for (i = 0; i < 20; i = i + 1) begin
            step(1'b1, 8'h82 + i[7:0], 1'b1);
            expect_eq(dout, 8'h80 + i, "gleichzeitig schreiben und lesen");
            expect_eq(empty | full, 0, "weder leer noch voll");
        end

        if (errors == 0) $display("PASS: tb_fifo_sync");
        else             $display("FAIL: tb_fifo_sync (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
