// tb_uart_tx — selbstprüfende Testbench für uart_tx.
//
// Ein einfacher Empfänger (Task recv_byte) tastet txd jeweils in der Bitmitte
// ab — so wie es ein echtes Terminal tut. Geprüft wird mit CLKS_PER_BIT = 4:
//   1. Ruhepegel 1 und ready = 1 nach Reset.
//   2. Mehrere Bytes kommen korrekt an (Startbit, LSB zuerst, Stoppbit).
//   3. ready ist während des Sendens 0; ein Byte dauert genau 10 Bitzeiten.
//   4. Zwei Bytes direkt hintereinander (valid bleibt 1) gehen nicht verloren.

`timescale 1ns / 1ps
`default_nettype none

module tb_uart_tx;

    localparam CLKS_PER_BIT = 4;
    localparam BIT_NS       = CLKS_PER_BIT * 20;

    reg        clk   = 1'b0;
    reg        rst   = 1'b1;
    reg  [7:0] data  = 8'h00;
    reg        valid = 1'b0;
    wire       ready;
    wire       txd;

    integer errors = 0;
    reg [7:0] got;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk   (clk),
        .rst   (rst),
        .data  (data),
        .valid (valid),
        .ready (ready),
        .txd_q (txd)
    );

    always #10 clk = ~clk;   // 50 MHz

    task fail(input [511:0] what);
        begin
            $display("FAIL: %0s bei t=%0t", what, $time);
            errors = errors + 1;
        end
    endtask

    // Wartet auf das Startbit und liest ein Byte in der jeweiligen Bitmitte.
    task recv_byte(output [7:0] value);
        integer i;
        begin
            @(negedge txd);
            #(BIT_NS / 2);
            if (txd !== 1'b0) fail("Startbit nicht 0");
            for (i = 0; i < 8; i = i + 1) begin
                #(BIT_NS);
                value[i] = txd;
            end
            #(BIT_NS);
            if (txd !== 1'b1) fail("Stoppbit nicht 1");
        end
    endtask

    // Legt ein Byte an, bis es übernommen wurde.
    task send_byte(input [7:0] value);
        begin
            @(negedge clk);
            data  = value;
            valid = 1'b1;
            @(posedge clk);
            while (!ready) @(posedge clk);
            @(negedge clk);
            valid = 1'b0;
        end
    endtask

    task send_and_check(input [7:0] value);
        begin
            fork
                send_byte(value);
                recv_byte(got);
            join
            if (got !== value) begin
                $display("FAIL: empfangen %h, erwartet %h bei t=%0t", got, value, $time);
                errors = errors + 1;
            end
            wait (ready);
        end
    endtask

    time t_start;

    initial begin
        $dumpfile("tb/build/tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);

        // 1. Reset
        repeat (3) @(posedge clk);
        #1;
        if (txd !== 1'b1)   fail("Ruhepegel nach Reset nicht 1");
        @(negedge clk) rst = 1'b0;
        @(posedge clk); #1;
        if (ready !== 1'b1) fail("ready nach Reset nicht 1");

        // 2. Einzelne Bytes
        send_and_check(8'h55);
        send_and_check(8'hA5);
        send_and_check(8'h00);
        send_and_check(8'hFF);
        send_and_check(8'h41);   // 'A'

        // 3. ready während des Sendens und Dauer eines Bytes
        @(negedge clk);
        data  = 8'h3C;
        valid = 1'b1;
        @(negedge clk);
        valid   = 1'b0;
        t_start = $time;
        if (ready !== 1'b0) fail("ready bleibt 1 trotz laufender Sendung");
        wait (ready);
        if ($time - t_start < 10 * BIT_NS - 20 || $time - t_start > 10 * BIT_NS + 20) begin
            $display("FAIL: Byte dauerte %0t statt %0d ns", $time - t_start, 10 * BIT_NS);
            errors = errors + 1;
        end

        // 4. Zwei Bytes direkt hintereinander, valid bleibt 1
        @(negedge clk);
        data  = 8'h12;
        valid = 1'b1;
        fork
            begin
                recv_byte(got);
                if (got !== 8'h12) fail("erstes Byte der Doppelsendung falsch");
                recv_byte(got);
                if (got !== 8'h34) fail("zweites Byte der Doppelsendung falsch");
            end
            begin
                @(posedge clk);            // erstes Byte übernommen
                @(negedge clk) data = 8'h34;
                wait (!ready); wait (ready);
                @(posedge clk);            // zweites Byte übernommen
                @(negedge clk) valid = 1'b0;
            end
        join
        wait (ready);

        if (errors == 0) $display("PASS: tb_uart_tx");
        else             $display("FAIL: tb_uart_tx (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: tb_uart_tx Timeout");
        $finish;
    end

endmodule

`default_nettype wire
