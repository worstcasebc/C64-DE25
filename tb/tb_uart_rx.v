// tb_uart_rx — selbstprüfende Testbench für uart_rx.
//
// Ein einfacher Sender (Task send_byte) legt die Bits so auf rxd, wie es ein
// Terminal tut. Geprüft wird mit CLKS_PER_BIT = 8:
//   1. Mehrere Bytes kommen korrekt an (LSB zuerst), valid genau einmal.
//   2. Zwei Bytes ohne Pause hintereinander gehen nicht verloren.
//   3. Ein Sender, der 3 % zu schnell oder zu langsam ist, wird verstanden.
//   4. Ein kurzer Störimpuls löst kein Byte aus.
//   5. Ein Byte ohne Stoppbit wird verworfen; danach geht es normal weiter.

`timescale 1ns / 1ps
`default_nettype none

module tb_uart_rx;

    localparam CLKS_PER_BIT = 8;
    localparam BIT_NS       = CLKS_PER_BIT * 20;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        rxd = 1'b1;
    wire [7:0] data;
    wire       valid;

    integer   errors  = 0;
    integer   n_valid = 0;
    reg [7:0] last    = 8'h00;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk     (clk),
        .rst     (rst),
        .rxd     (rxd),
        .data_q  (data),
        .valid_q (valid)
    );

    always #10 clk = ~clk;   // 50 MHz

    always @(posedge clk) begin
        if (valid) begin
            n_valid = n_valid + 1;
            last    = data;
        end
    end

    // Sendet ein Byte mit bit_ns Nanosekunden pro Bit; stop = Pegel des Stoppbits.
    task send_byte(input [7:0] value, input integer bit_ns, input stop);
        integer i;
        begin
            rxd = 1'b0;
            #(bit_ns);
            for (i = 0; i < 8; i = i + 1) begin
                rxd = value[i];
                #(bit_ns);
            end
            rxd = stop;
            #(bit_ns);
            rxd = 1'b1;
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
        $dumpfile("tb/build/tb_uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);

        repeat (3) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        #(BIT_NS * 2 + 3);      // absichtlich nicht im Taktraster

        // 1. einzelne Bytes
        send_byte(8'h41, BIT_NS, 1'b1);
        #(BIT_NS);
        expect_eq(n_valid, 1, "Anzahl nach erstem Byte");
        expect_eq(last, 8'h41, "erstes Byte");
        send_byte(8'h00, BIT_NS, 1'b1);
        #(BIT_NS);
        expect_eq(last, 8'h00, "Byte 00");
        send_byte(8'hFF, BIT_NS, 1'b1);
        #(BIT_NS);
        expect_eq(last, 8'hFF, "Byte FF");
        expect_eq(n_valid, 3, "Anzahl nach drei Bytes");

        // 2. zwei Bytes ohne Pause
        send_byte(8'hA5, BIT_NS, 1'b1);
        send_byte(8'h5A, BIT_NS, 1'b1);
        #(BIT_NS);
        expect_eq(n_valid, 5, "Anzahl nach Doppelbyte");
        expect_eq(last, 8'h5A, "zweites Byte des Doppels");

        // 3. Sender 3 % zu schnell bzw. zu langsam
        send_byte(8'h96, BIT_NS * 97 / 100, 1'b1);
        #(BIT_NS);
        expect_eq(last, 8'h96, "Byte von zu schnellem Sender");
        send_byte(8'h69, BIT_NS * 103 / 100, 1'b1);
        #(BIT_NS);
        expect_eq(last, 8'h69, "Byte von zu langsamem Sender");
        expect_eq(n_valid, 7, "Anzahl nach Toleranztest");

        // 4. Störimpuls (kürzer als eine halbe Bitzeit)
        rxd = 1'b0;
        #(BIT_NS / 4);
        rxd = 1'b1;
        #(BIT_NS * 12);
        expect_eq(n_valid, 7, "Anzahl nach Stoerimpuls");

        // 5. fehlendes Stoppbit
        send_byte(8'h33, BIT_NS, 1'b0);
        #(BIT_NS * 3);
        expect_eq(n_valid, 7, "Anzahl nach Byte ohne Stoppbit");
        send_byte(8'hC3, BIT_NS, 1'b1);
        #(BIT_NS);
        expect_eq(n_valid, 8, "Anzahl nach Erholung");
        expect_eq(last, 8'hC3, "Byte nach Erholung");

        if (errors == 0) $display("PASS: tb_uart_rx");
        else             $display("FAIL: tb_uart_rx (%0d Fehler)", errors);
        $finish;
    end

endmodule

`default_nettype wire
