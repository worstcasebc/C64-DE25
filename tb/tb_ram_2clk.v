// tb_ram_2clk — selbstprüfende Testbench für ram_2clk.
//
// Zwei Takte ohne festes Verhältnis (100 MHz schreibt, 31,5 MHz liest).
// Geprüft wird:
//   1. Nach dem Start steht überall 0.
//   2. Alle Zellen beschreiben, danach alle lesen: jede liefert ihren Wert.
//   3. Lesedaten erscheinen genau eine Flanke nach der Adresse.
//   4. Ohne wr_en ändert sich nichts.

`timescale 1ns / 1ps
`default_nettype none

module tb_ram_2clk;

    localparam ADDR_W = 6;
    localparam N      = 1 << ADDR_W;

    reg               wr_clk = 1'b0;
    reg               wr_en = 1'b0;
    reg  [ADDR_W-1:0] wr_addr = 0;
    reg  [7:0]        wr_din = 8'h00;
    reg               rd_clk = 1'b0;
    reg  [ADDR_W-1:0] rd_addr = 0;
    wire [7:0]        rd_dout;

    integer errors = 0;
    integer i;

    ram_2clk #(.ADDR_W(ADDR_W), .DATA_W(8)) dut (
        .wr_clk    (wr_clk),
        .wr_en     (wr_en),
        .wr_addr   (wr_addr),
        .wr_din    (wr_din),
        .rd_clk    (rd_clk),
        .rd_addr   (rd_addr),
        .rd_dout_q (rd_dout)
    );

    always #5      wr_clk = ~wr_clk;
    always #15.873 rd_clk = ~rd_clk;

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    // Wert, der in Zelle a steht
    function [7:0] pattern(input integer a);
        pattern = (a * 37 + 11) & 8'hFF;
    endfunction

    initial begin
        $dumpfile("tb/build/tb_ram_2clk.vcd");
        $dumpvars(0, tb_ram_2clk);

        // 1. Startinhalt
        for (i = 0; i < N; i = i + 1) begin
            @(negedge rd_clk) rd_addr = i[ADDR_W-1:0];
            @(negedge rd_clk) expect_eq(rd_dout, 0, "Startinhalt");
        end

        // 2. alles schreiben, dann alles lesen
        for (i = 0; i < N; i = i + 1) begin
            @(negedge wr_clk);
            wr_addr = i[ADDR_W-1:0];
            wr_din  = pattern(i);
            wr_en   = 1'b1;
        end
        @(negedge wr_clk) wr_en = 1'b0;
        for (i = 0; i < N; i = i + 1) begin
            @(negedge rd_clk) rd_addr = i[ADDR_W-1:0];
            @(negedge rd_clk) expect_eq(rd_dout, pattern(i), "gelesener Wert");
        end

        // 3. genau eine Flanke Verzögerung
        @(negedge rd_clk) rd_addr = 5;
        @(negedge rd_clk) rd_addr = 9;
        expect_eq(rd_dout, pattern(5), "Wert der vorigen Adresse");
        @(negedge rd_clk) expect_eq(rd_dout, pattern(9), "Wert der neuen Adresse");

        // 4. ohne wr_en kein Schreiben
        @(negedge wr_clk);
        wr_addr = 9;
        wr_din  = 8'hEE;
        repeat (4) @(negedge wr_clk);
        @(negedge rd_clk) rd_addr = 9;
        @(negedge rd_clk) expect_eq(rd_dout, pattern(9), "unveraendert ohne wr_en");

        if (errors == 0) $display("PASS: tb_ram_2clk");
        else             $display("FAIL: tb_ram_2clk (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
