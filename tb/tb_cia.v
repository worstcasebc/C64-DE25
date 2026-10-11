// tb_cia — selbstprüfende Testbench für cia.
//
// 1. Nach Reset: kein IRQ, keine Meldung, Ports sind Eingänge.
// 2. Timer A fortlaufend mit Startwert 4: Unterlauf alle 5 Schritte, IRQ
//    kommt, ICR liest $81 und löscht dabei Meldung und IRQ.
// 3. Gesperrter Interrupt: Die Meldung steht in ICR, aber irq bleibt 0.
// 4. Einmal-Modus: genau ein Unterlauf, danach steht der Timer (Startbit 0).
// 5. Zählerstand lässt sich lesen; "Startwert laden" (CRA Bit 4) wirkt
//    sofort und wird nicht gespeichert.
// 6. Ohne tick steht der Timer; ebenso nach dem Löschen des Startbits.
// tick und en sind hier dasselbe Signal: Die CPU ist nie angehalten.
// 7. Ports: Ausgänge liefern das Register, Eingänge den Pegel am Pin.
// 8. Schreiben ohne sel wird ignoriert.

`timescale 1ns / 1ps
`default_nettype none

module tb_cia;

    reg        clk   = 1'b0;
    reg        rst   = 1'b1;
    reg        en    = 1'b1;
    reg        sel   = 1'b0;
    reg        we    = 1'b0;
    reg  [3:0] addr  = 4'h0;
    reg  [7:0] din   = 8'h00;
    reg  [7:0] pa_in = 8'hFF;
    reg  [7:0] pb_in = 8'hFF;
    wire [7:0] dout;
    wire       irq;
    wire [7:0] pa_out;
    wire [7:0] pb_out;

    integer errors   = 0;
    integer edges    = 0;       // Taktflanken seit Simulationsbeginn
    integer irq_edge = 0;       // Flanke, nach der irq zuletzt auf 1 ging
    integer first_irq;
    reg [7:0] seen;

    cia dut (
        .clk    (clk),
        .rst    (rst),
        .tick   (en),
        .en     (en),
        .sel    (sel),
        .we     (we),
        .addr   (addr),
        .din    (din),
        .dout_q (dout),
        .irq    (irq),
        .pa_out (pa_out),
        .pb_out (pb_out),
        .pa_in  (pa_in),
        .pb_in  (pb_in)
    );

    always #10 clk = ~clk;
    always @(posedge clk) edges = edges + 1;
    always @(posedge irq) irq_edge = edges;

    task bus_write(input [3:0] a, input [7:0] d);
        begin
            @(negedge clk);
            sel = 1'b1; we = 1'b1; addr = a; din = d;
            @(posedge clk); #1;
            sel = 1'b0; we = 1'b0;
        end
    endtask

    task bus_read(input [3:0] a);       // Ergebnis steht danach in dout
        begin
            @(negedge clk);
            sel = 1'b1; we = 1'b0; addr = a;
            @(posedge clk); #1;
            sel = 1'b0;
        end
    endtask

    task idle(input integer n);
        begin
            repeat (n) @(posedge clk);
            #1;
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
        $dumpfile("tb/build/tb_cia.vcd");
        $dumpvars(0, tb_cia);

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 1. Reset
        expect_eq(irq, 0, "irq nach Reset");
        bus_read(4'hD);  expect_eq(dout, 8'h00, "ICR nach Reset");
        bus_read(4'h1);  expect_eq(dout, 8'hFF, "PRB nach Reset (Eingang)");
        expect_eq(pa_out, 8'hFF, "pa_out nach Reset");

        // 2. fortlaufender Timer, Startwert 4
        bus_write(4'h4, 8'h04);
        bus_write(4'h5, 8'h00);
        bus_write(4'hD, 8'h81);         // Unterlauf Timer A freigeben
        bus_write(4'hE, 8'h11);         // Start + Startwert laden
        wait (irq);
        #1 first_irq = irq_edge;
        idle(1);
        bus_read(4'hD);
        expect_eq(dout, 8'h81, "ICR beim ersten Unterlauf");
        expect_eq(irq, 0, "irq nach Lesen von ICR");
        wait (irq);
        #1 expect_eq(irq_edge - first_irq, 5, "Schritte zwischen Unterlaeufen");
        bus_read(4'hD);
        bus_read(4'hD);
        expect_eq(dout, 8'h00, "ICR beim zweiten Lesen");

        // 3. Interrupt sperren: Meldung ja, IRQ nein
        bus_write(4'hD, 8'h01);
        idle(8);
        expect_eq(irq, 0, "irq bei gesperrtem Interrupt");
        bus_read(4'hD);
        expect_eq(dout, 8'h01, "ICR bei gesperrtem Interrupt");

        // 4. Einmal-Modus
        bus_write(4'hD, 8'h81);
        bus_write(4'hE, 8'h19);         // Start + laden + einmalig
        wait (irq);
        bus_read(4'hE);
        expect_eq(dout, 8'h08, "CRA nach einmaligem Ablauf");
        bus_read(4'hD);
        expect_eq(dout, 8'h81, "ICR nach einmaligem Ablauf");
        idle(12);
        expect_eq(irq, 0, "kein weiterer Unterlauf im Einmal-Modus");

        // 5. Zählerstand lesen, Startwert laden
        bus_write(4'h4, 8'h34);
        bus_write(4'h5, 8'h12);         // Timer steht: wird sofort geladen
        bus_read(4'h4);  expect_eq(dout, 8'h34, "Timer low nach Laden");
        bus_read(4'h5);  expect_eq(dout, 8'h12, "Timer high nach Laden");
        bus_write(4'hE, 8'h01);         // fortlaufend starten
        idle(3);
        bus_read(4'h4);                 // gelesen wird der Stand vor diesem Schritt
        expect_eq(dout, 8'h31, "Timer low nach 3 Schritten");
        bus_write(4'hE, 8'h11);         // Startwert neu laden
        bus_read(4'h4);
        expect_eq(dout, 8'h34, "Timer low direkt nach erneutem Laden");
        bus_read(4'hE);
        expect_eq(dout, 8'h01, "CRA: Bit 4 wird nicht gespeichert");

        // 6. en = 0: Timer steht. Zwischen zwei Lesezugriffen liegt dann
        //    nur der eine Schritt des ersten Zugriffs.
        bus_read(4'h4);
        seen = dout;
        @(negedge clk) en = 1'b0;
        idle(10);
        en = 1'b1;
        bus_read(4'h4);
        expect_eq(dout, seen - 8'd1, "Timer bei en=0");
        bus_write(4'hE, 8'h00);         // Startbit löschen
        bus_read(4'h4);
        seen = dout;
        idle(5);
        bus_read(4'h4);
        expect_eq(dout, seen, "Timer steht nach Stopp");

        // 7. Ports
        bus_write(4'h2, 8'hFF);
        bus_write(4'h0, 8'hA5);
        expect_eq(pa_out, 8'hA5, "pa_out als Ausgang");
        bus_read(4'h0);  expect_eq(dout, 8'hA5, "PRA lesen als Ausgang");
        bus_write(4'h2, 8'h0F);
        pa_in = 8'h3C;
        expect_eq(pa_out, 8'hF5, "pa_out halb Eingang");
        bus_read(4'h0);  expect_eq(dout, 8'h35, "PRA lesen halb Eingang");
        pb_in = 8'h7E;
        bus_read(4'h1);  expect_eq(dout, 8'h7E, "PRB lesen als Eingang");
        bus_read(4'h2);  expect_eq(dout, 8'h0F, "DDRA lesen");

        // 8. ohne sel
        @(negedge clk);
        sel = 1'b0; we = 1'b1; addr = 4'h2; din = 8'h00;
        @(posedge clk); #1;
        we = 1'b0;
        bus_read(4'h2);  expect_eq(dout, 8'h0F, "DDRA nach Schreiben ohne sel");

        if (errors == 0) $display("PASS: tb_cia");
        else             $display("FAIL: tb_cia (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #1_000_000;
        $display("FAIL: tb_cia Timeout");
        $finish;
    end

endmodule

`default_nettype wire
