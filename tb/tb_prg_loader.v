// tb_prg_loader — selbstprüfende Testbench für prg_loader.
//
// Die Testbench spielt uart_rx (Bytes mit Abstand) und das RAM (bestätigt
// jeden Schreibwunsch nach ein paar Takten und merkt sich den Inhalt).
// 1. Bytes außerhalb eines Ladeblocks gehen als Tastendrücke weiter.
// 2. Ein Ladeblock schreibt seine Daten ab der Adresse ins RAM; weder das
//    Startbyte noch Kopf oder Daten erscheinen als Tastendruck.
// 3. Danach gelten Bytes wieder als Tastendrücke.
// 4. Ein Block über die Grenze $FFFF hinaus läuft bei $0000 weiter; ein
//    Datenbyte $FF mitten im Block ist ein normales Datenbyte.
// 5. Ein Block der Länge 0 schreibt nichts.
// 6. Ein abgebrochener Block endet nach der Wartezeit; spätere Bytes sind
//    wieder Tastendrücke.

`timescale 1ns / 1ps
`default_nettype none

module tb_prg_loader;

    localparam TIMEOUT = 200;

    reg         clk      = 1'b0;
    reg         rst      = 1'b1;
    reg  [7:0]  rx_data  = 8'h00;
    reg         rx_valid = 1'b0;
    wire [7:0]  key_data;
    wire        key_valid;
    wire        dma_req;
    wire [15:0] dma_addr;
    wire [7:0]  dma_data;
    reg         dma_ack  = 1'b0;
    wire        active;

    integer errors = 0;
    integer i;

    prg_loader #(.TIMEOUT_CLKS(TIMEOUT)) dut (
        .clk       (clk),
        .rst       (rst),
        .rx_data   (rx_data),
        .rx_valid  (rx_valid),
        .key_data  (key_data),
        .key_valid (key_valid),
        .dma_req   (dma_req),
        .dma_addr  (dma_addr),
        .dma_data  (dma_data),
        .dma_ack   (dma_ack),
        .active    (active)
    );

    always #10 clk = ~clk;

    // --- RAM-Modell: bestätigt nach 3 Takten ---------------------------------
    reg [7:0] mem [0:65535];
    integer   n_writes = 0;
    integer   delay    = 0;

    always @(posedge clk) begin
        dma_ack <= 1'b0;
        if (dma_req && !dma_ack) begin
            if (delay == 2) begin
                mem[dma_addr] = dma_data;
                n_writes = n_writes + 1;
                dma_ack <= 1'b1;
                delay = 0;
            end else begin
                delay = delay + 1;
            end
        end
    end

    // --- Protokoll der Tastendrücke -----------------------------------------
    reg [7:0] key_log [0:15];
    integer   n_keys = 0;

    always @(posedge clk) begin
        if (key_valid) begin
            key_log[n_keys] = key_data;
            n_keys = n_keys + 1;
        end
    end

    task send(input [7:0] value);       // ein Byte, danach 10 Takte Pause
        begin
            @(negedge clk);
            rx_data = value; rx_valid = 1'b1;
            @(negedge clk);
            rx_valid = 1'b0;
            repeat (10) @(negedge clk);
        end
    endtask

    task send_header(input [15:0] address, input [15:0] length);
        begin
            send(8'hFF);
            send(address[7:0]);
            send(address[15:8]);
            send(length[7:0]);
            send(length[15:8]);
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
        $dumpfile("tb/build/tb_prg_loader.vcd");
        $dumpvars(0, tb_prg_loader);

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 1. Tastendrücke
        send("A");
        send(8'h0D);
        expect_eq(n_keys, 2, "Anzahl Tastendruecke");
        expect_eq(key_log[0], "A", "erster Tastendruck");
        expect_eq(key_log[1], 8'h0D, "zweiter Tastendruck");
        expect_eq(active, 0, "active ausserhalb eines Blocks");

        // 2. Ladeblock: 5 Bytes ab $0801
        send_header(16'h0801, 16'd5);
        expect_eq(active, 1, "active im Block");
        for (i = 0; i < 5; i = i + 1) send(8'h40 + i[7:0]);
        expect_eq(active, 0, "active nach dem Block");
        expect_eq(n_writes, 5, "Anzahl Schreibzugriffe");
        for (i = 0; i < 5; i = i + 1) expect_eq(mem[16'h0801 + i], 8'h40 + i, "Blockinhalt");
        expect_eq(dma_req, 0, "dma_req nach dem Block");
        expect_eq(n_keys, 2, "keine Tastendruecke aus dem Block");

        // 3. danach wieder Tastendrücke
        send("B");
        expect_eq(n_keys, 3, "Tastendruck nach dem Block");
        expect_eq(key_log[2], "B", "Tastendruck nach dem Block");

        // 4. über $FFFF hinaus, mit Datenbyte $FF
        send_header(16'hFFFE, 16'd3);
        send(8'h11); send(8'hFF); send(8'h33);
        expect_eq(mem[16'hFFFE], 8'h11, "Zelle FFFE");
        expect_eq(mem[16'hFFFF], 8'hFF, "Zelle FFFF");
        expect_eq(mem[16'h0000], 8'h33, "Zelle 0000");
        expect_eq(active, 0, "active nach Block ueber die Grenze");

        // 5. Länge 0
        n_writes = 0;
        send_header(16'h1000, 16'd0);
        expect_eq(active, 0, "active nach leerem Block");
        send("C");
        expect_eq(n_writes, 0, "Schreibzugriffe bei leerem Block");
        expect_eq(key_log[3], "C", "Tastendruck nach leerem Block");

        // 6. abgebrochener Block
        send_header(16'h2000, 16'd100);
        send(8'h77);
        expect_eq(active, 1, "active im abgebrochenen Block");
        repeat (TIMEOUT + 20) @(negedge clk);
        expect_eq(active, 0, "active nach der Wartezeit");
        send("D");
        expect_eq(n_keys, 5, "Tastendruck nach abgebrochenem Block");
        expect_eq(key_log[4], "D", "Tastendruck nach abgebrochenem Block");
        expect_eq(n_writes, 1, "Schreibzugriffe im abgebrochenen Block");

        if (errors == 0) $display("PASS: tb_prg_loader");
        else             $display("FAIL: tb_prg_loader (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: tb_prg_loader Timeout");
        $finish;
    end

endmodule

`default_nettype wire
