// tb_soc_c64 — selbstprüfende Testbench für den C64-Rechner.
// Simulator: Questa
//
// Lässt die Test-ROMs (sw/asm/banktest.s) laufen und prüft, dass am UART-Pin
// genau der erwartete Text erscheint. Das Programm schaltet das Banking um
// und meldet je Bereich OK oder den falsch gelesenen Wert; zuletzt zählt es
// Timer-Interrupts beider CIAs (IRQ und NMI). Damit sind CPU, CPU-Port,
// Address-Decoder, RAM unter den ROMs, alle drei ROMs und beide
// Interrupt-Wege gemeinsam getestet — mit dem echten VIC-II am Bus, der die
// CPU bei eingeschaltetem Bildschirm regelmäßig anhält. Das Bild selbst
// prüft tb_c64_video.
//
// Der Rechner läuft mit PIX_DIV = 1 (8 statt 32 Systemtakte pro CPU-Takt),
// das spart Rechenzeit.
//
// Während das Programm läuft, schreibt die Testbench über den DMA-Anschluss
// 64 Bytes nach $C000 (dort arbeitet das Programm nicht). Geprüft wird, dass
// sie im RAM ankommen und die CPU trotz der ausgesetzten Schritte denselben
// Text ausgibt.
//
// Vom SID wird hier nur geprüft, dass ein Schreibzugriff auf $D418 bei ihm
// ankommt; seinen Ton prüft tb_sid_tone. Mit PIX_DIV = 1 hat er zu wenige
// Takte, um Ton zu berechnen.
//
// Für den Test des seriellen Busses spielt die Testbench ein Laufwerk, das
// auf ATN antwortet, indem es DATA auf 0 zieht.
//
// Zum Schluss die Taste RESTORE: Jeder Druck muss genau einen NMI auslösen,
// auch wenn die Taste lange gehalten wird. Die NMI-Routine des Testprogramms
// zählt mit; die Testbench liest den Zähler im RAM.

`timescale 1ns / 1ps
`default_nettype none

module tb_soc_c64;

    localparam CLKS_PER_BIT = 4;
    localparam LEN          = 154;  // muss zur Länge von EXPECTED passen
    localparam [8*LEN-1:0] EXPECTED = {
        "C64-Speicherkarte\015\n",
        "BASIC-ROM  OK\015\n",
        "RAM $A000  OK\015\n",
        "CHAR-ROM   OK\015\n",
        "RAM $D000  OK\015\n",
        "RAM $E000  OK\015\n",
        "CPU-PORT   OK\015\n",
        "CIA-IRQ    OK\015\n",
        "CIA-NMI    OK\015\n",
        "IEC-BUS    OK\015\n"
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
    reg         restore = 1'b0;
    wire        iec_atn;
    reg [7:0]   nmi_before;

    // Zähler der NMI-Routine im Testprogramm (nmi_count in banktest.s, die
    // sechste Variable in der Zeropage ab $02).
    localparam NMI_COUNT = 16'h0007;

    soc_c64 #(.PIX_DIV(1), .UART_CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk        (clk),
        .rst        (rst),
        .uart_txd   (txd),
        .keys       (64'd0),
        .restore    (restore),
        .iec_atn_o  (iec_atn),
        .iec_clk_o  (),
        .iec_data_o (),
        .iec_clk_i  (1'b1),
        .iec_data_i (iec_atn),      // wie ein Laufwerk: auf ATN mit DATA antworten
        .dma_req    (dma_req),
        .dma_addr   (dma_addr),
        .dma_data   (dma_data),
        .dma_ack    (dma_ack),
        .pix_en     (),
        .vic_color  (),
        .vic_hblank (),
        .vic_vblank (),
        .sid_audio  (),
        .cpu_tick   ()
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

        // Zugriff auf den SID: Das Programm schreibt $0F nach $D418. Das
        // Register lässt sich nicht zurücklesen, deshalb der Blick hinein.
        repeat (200_000) @(posedge clk);
        if (dut.u_sid.Filter_Mode_Vol[0] !== 8'h0F) begin
            $display("FAIL: SID-Register $18 ist %h, erwartet 0f", dut.u_sid.Filter_Mode_Vol[0]);
            dma_errors = dma_errors + 1;
        end

        // RESTORE: Die CIA 2 ist inzwischen still, der Zaehler steht.
        nmi_before = dut.u_ram.mem[NMI_COUNT];
        repeat (2000) @(posedge clk);
        if (dut.u_ram.mem[NMI_COUNT] !== nmi_before) begin
            $display("FAIL: NMI-Zaehler laeuft ohne RESTORE");
            dma_errors = dma_errors + 1;
        end
        for (k = 1; k <= 2; k = k + 1) begin
            @(negedge clk) restore = 1'b1;
            repeat (4000) @(posedge clk);       // 500 CPU-Takte gehalten
            if (dut.u_ram.mem[NMI_COUNT] !== nmi_before + k[7:0]) begin
                $display("FAIL: RESTORE gehalten, Druck %0d: Zaehler %0d, erwartet %0d", k,
                         dut.u_ram.mem[NMI_COUNT], nmi_before + k[7:0]);
                dma_errors = dma_errors + 1;
            end
            @(negedge clk) restore = 1'b0;
            repeat (2000) @(posedge clk);
            if (dut.u_ram.mem[NMI_COUNT] !== nmi_before + k[7:0]) begin
                $display("FAIL: RESTORE losgelassen, Druck %0d: Zaehler %0d, erwartet %0d", k,
                         dut.u_ram.mem[NMI_COUNT], nmi_before + k[7:0]);
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
