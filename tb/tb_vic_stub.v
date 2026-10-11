// tb_vic_stub — selbstprüfende Testbench für vic_stub.
//
// 1. Nach Reset sind beide Farben 0 (Schwarz).
// 2. $D020/$D021 schreiben und zurücklesen; nur die unteren 4 Bit zählen,
//    die oberen lesen als 1.
// 3. Die Register wiederholen sich alle 64 Adressen ($D060 = $D020).
// 4. Andere Register lesen $00 (auch $D012) und nehmen keine Werte an.
// 5. Schreiben ohne en bzw. ohne sel wird ignoriert.

`timescale 1ns / 1ps
`default_nettype none

module tb_vic_stub;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        en  = 1'b0;
    reg        sel = 1'b0;
    reg        we  = 1'b0;
    reg  [9:0] bus_addr = 10'h000;      // Adresse innerhalb von $D000-$D3FF
    reg  [7:0] din = 8'h00;
    wire [7:0] dout;
    wire [3:0] border;
    wire [3:0] bg;

    integer errors = 0;

    vic_stub dut (
        .clk            (clk),
        .rst            (rst),
        .en             (en),
        .sel            (sel),
        .we             (we),
        .addr           (bus_addr[5:0]),
        .din            (din),
        .dout_q         (dout),
        .border_color_q (border),
        .bg_color_q     (bg)
    );

    always #10 clk = ~clk;

    // Ein Buszugriff: Signale anlegen, eine Flanke abwarten.
    task access(input enable, input select, input write, input [9:0] a, input [7:0] d);
        begin
            @(negedge clk);
            en = enable; sel = select; we = write; bus_addr = a; din = d;
            @(posedge clk); #1;
        end
    endtask

    task expect_val(input [7:0] got, input [7:0] want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %h, erwartet %h bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    task expect_read(input [9:0] a, input [7:0] want, input [255:0] what);
        begin
            access(1'b1, 1'b1, 1'b0, a, 8'h00);
            expect_val(dout, want, what);
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_vic_stub.vcd");
        $dumpvars(0, tb_vic_stub);

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 1. Reset
        expect_val({border, bg}, 8'h00, "Farben nach Reset");

        // 2. Schreiben und zurücklesen
        access(1'b1, 1'b1, 1'b1, 10'h020, 8'h0E);
        access(1'b1, 1'b1, 1'b1, 10'h021, 8'hA6);     // obere Bits zählen nicht
        expect_val({border, bg}, 8'hE6, "Farben nach Schreiben");
        expect_read(10'h020, 8'hFE, "$D020 lesen");
        expect_read(10'h021, 8'hF6, "$D021 lesen");

        // 3. Spiegelung alle 64 Adressen
        access(1'b1, 1'b1, 1'b1, 10'h060, 8'h03);
        expect_val({border, bg}, 8'h36, "Farben nach Schreiben auf $D060");
        expect_read(10'h3E1, 8'hF6, "$D3E1 lesen");

        // 4. andere Register
        expect_read(10'h012, 8'h00, "$D012 lesen");
        access(1'b1, 1'b1, 1'b1, 10'h011, 8'hFF);
        expect_read(10'h011, 8'h00, "$D011 lesen nach Schreiben");
        expect_val({border, bg}, 8'h36, "Farben nach fremdem Register");

        // 5. ohne en bzw. ohne sel
        access(1'b0, 1'b1, 1'b1, 10'h020, 8'h01);
        access(1'b1, 1'b0, 1'b1, 10'h021, 8'h01);
        expect_val({border, bg}, 8'h36, "Farben nach Schreiben ohne en/sel");

        if (errors == 0) $display("PASS: tb_vic_stub");
        else             $display("FAIL: tb_vic_stub (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
