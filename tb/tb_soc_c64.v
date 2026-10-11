// tb_soc_c64 — selbstprüfende Testbench für den C64-Rechner.
// Simulator: Questa
//
// Lässt die Test-ROMs (sw/asm/banktest.s) laufen und prüft, dass am UART-Pin
// genau der erwartete Text erscheint. Das Programm schaltet das Banking um
// und meldet je Bereich OK oder den falsch gelesenen Wert; zuletzt zählt es
// Timer-Interrupts der CIA. Damit sind CPU, CPU-Port, Address-Decoder, RAM
// unter den ROMs, alle drei ROMs und der IRQ-Weg gemeinsam getestet — jetzt
// mit dem echten VIC-II am Bus, der die CPU bei eingeschaltetem Bildschirm
// regelmäßig anhält. Das Bild selbst prüft tb_c64_video.
//
// Der Rechner läuft mit PIX_DIV = 1 (8 statt 32 Systemtakte pro CPU-Takt),
// das spart Rechenzeit.
//
// Während das Programm läuft, schreibt die Testbench über den DMA-Anschluss
// 64 Bytes nach $C000 (dort arbeitet das Programm nicht). Geprüft wird, dass
// sie im RAM ankommen und die CPU trotz der ausgesetzten Schritte denselben
// Text ausgibt.

`timescale 1ns / 1ps
`default_nettype none

module tb_soc_c64;

    localparam CLKS_PER_BIT = 4;
    localparam LEN          = 124;  // muss zur Länge von EXPECTED passen
    localparam [8*LEN-1:0] EXPECTED = {
        "C64-Speicherkarte\015\n",
        "BASIC-ROM  OK\015\n",
        "RAM $A000  OK\015\n",
        "CHAR-ROM   OK\015\n",
        "RAM $D000  OK\015\n",
        "RAM $E000  OK\015\n",
        "CPU-PORT   OK\015\n",
        "CIA-IRQ    OK\015\n"
    };

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    wire        txd;
    wire        done;
    wire [31:0] errors;
    reg         dma_req  = 1'b0;
    reg  [15:0] dma_addr = 16'h0000;
    reg  [7:0]  dma_data = 8'h00;
    wire        dma_ack;
    integer     dma_errors = 0;
    integer     k;

    soc_c64 #(.PIX_DIV(1), .UART_CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk        (clk),
        .rst        (rst),
        .uart_txd   (txd),
        .keys       (64'd0),
        .dma_req    (dma_req),
        .dma_addr   (dma_addr),
        .dma_data   (dma_data),
        .dma_ack    (dma_ack),
        .pix_en     (),
        .vic_color  (),
        .vic_hblank (),
        .vic_vblank ()
    );

    uart_rx_check #(.BIT_NS(CLKS_PER_BIT * 20), .LEN(LEN), .EXPECTED(EXPECTED)) rx (
        .rxd    (txd),
        .done   (done),
        .errors (errors)
    );

    always #10 clk = ~clk;

    // DMA: Schreibwunsch anlegen und halten, bis er bestätigt ist.
    initial begin
        wait (!rst);
        repeat (2000) @(posedge clk);
        for (k = 0; k < 64; k = k + 1) begin
            @(negedge clk);
            dma_addr = 16'hC000 + k[15:0];
            dma_data = 8'h80 + k[7:0];
            dma_req  = 1'b1;
            @(posedge clk);
            while (!dma_ack) @(posedge clk);
            @(negedge clk);
            dma_req = 1'b0;
            repeat (137) @(posedge clk);
        end
    end

    initial begin
        repeat (20) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        wait (done);

        for (k = 0; k < 64; k = k + 1) begin
            if (dut.u_ram.mem[16'hC000 + k] !== 8'h80 + k[7:0]) begin
                $display("FAIL: DMA-Byte %0d ist %h, erwartet %h", k,
                         dut.u_ram.mem[16'hC000 + k], 8'h80 + k[7:0]);
                dma_errors = dma_errors + 1;
            end
        end

        if (errors + dma_errors == 0) $display("PASS: tb_soc_c64");
        else $display("FAIL: tb_soc_c64 (%0d Fehler)", errors + dma_errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: tb_soc_c64 Timeout (fertig=%b)", done);
        $finish;
    end

endmodule

`default_nettype wire
