// tb_soc_c64 — selbstprüfende Testbench für den Rechner mit C64-Speicherkarte.
//
// Lässt die Test-ROMs (sw/asm/banktest.s) laufen und prüft, dass am UART-Pin
// genau der erwartete Text erscheint. Das Programm schaltet das Banking um
// und meldet je Bereich OK oder den falsch gelesenen Wert. Damit sind CPU,
// CPU-Port, Address-Decoder, RAM unter den ROMs und alle drei ROMs gemeinsam
// getestet. Der Video-Anschluss bleibt hier unbenutzt (siehe tb_c64_video).
//
// Zwei Instanzen laufen parallel: CPU_DIV = 1 (CPU in jedem Takt) und
// CPU_DIV = 3 (Taktfreigabe jeden dritten Takt). Beide müssen denselben Text
// liefern.

`timescale 1ns / 1ps
`default_nettype none

module tb_soc_c64;

    localparam CLKS_PER_BIT = 4;
    localparam LEN          = 109;  // muss zur Länge von EXPECTED passen
    localparam [8*LEN-1:0] EXPECTED = {
        "C64-Speicherkarte\015\n",
        "BASIC-ROM  OK\015\n",
        "RAM $A000  OK\015\n",
        "CHAR-ROM   OK\015\n",
        "RAM $D000  OK\015\n",
        "RAM $E000  OK\015\n",
        "CPU-PORT   OK\015\n"
    };

    reg  clk = 1'b0;
    reg  rst = 1'b1;
    wire txd_div1;
    wire txd_div3;
    wire done_div1;
    wire done_div3;
    wire [31:0] errors_div1;
    wire [31:0] errors_div3;

    soc_c64 #(.CPU_DIV(1), .UART_CLKS_PER_BIT(CLKS_PER_BIT)) dut_div1 (
        .clk            (clk),
        .rst            (rst),
        .uart_txd       (txd_div1),
        .vid_en         (1'b0),
        .vid_ram_addr   (16'h0000),
        .vid_ram_dout   (),
        .vid_color_addr (10'h000),
        .vid_color_dout (),
        .vid_char_addr  (12'h000),
        .vid_char_dout  (),
        .border_color   (),
        .bg_color       ()
    );

    soc_c64 #(.CPU_DIV(3), .UART_CLKS_PER_BIT(CLKS_PER_BIT)) dut_div3 (
        .clk            (clk),
        .rst            (rst),
        .uart_txd       (txd_div3),
        .vid_en         (1'b0),
        .vid_ram_addr   (16'h0000),
        .vid_ram_dout   (),
        .vid_color_addr (10'h000),
        .vid_color_dout (),
        .vid_char_addr  (12'h000),
        .vid_char_dout  (),
        .border_color   (),
        .bg_color       ()
    );

    uart_rx_check #(.BIT_NS(CLKS_PER_BIT * 20), .LEN(LEN), .EXPECTED(EXPECTED)) rx_div1 (
        .rxd    (txd_div1),
        .done   (done_div1),
        .errors (errors_div1)
    );

    uart_rx_check #(.BIT_NS(CLKS_PER_BIT * 20), .LEN(LEN), .EXPECTED(EXPECTED)) rx_div3 (
        .rxd    (txd_div3),
        .done   (done_div3),
        .errors (errors_div3)
    );

    always #10 clk = ~clk;   // 50 MHz

    initial begin
        $dumpfile("tb/build/tb_soc_c64.vcd");
        $dumpvars(0, tb_soc_c64);
    end

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        wait (done_div1 && done_div3);

        if (errors_div1 + errors_div3 == 0) $display("PASS: tb_soc_c64");
        else $display("FAIL: tb_soc_c64 (%0d Fehler)", errors_div1 + errors_div3);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("FAIL: tb_soc_c64 Timeout (div1 fertig=%b, div3 fertig=%b)", done_div1, done_div3);
        $finish;
    end

endmodule

`default_nettype wire
