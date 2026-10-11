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
// 9. Timer B: zählt wie Timer A CPU-Takte und meldet sich in ICR Bit 1.
// 10. Timer B zählt Unterläufe von Timer A (CRB Bit 6): So entsteht ein
//     langer Zähler aus beiden.
// 11. Uhr: zählt Zehntel aus dem 50-Hz-Takt, mit Überträgen bis in die
//     Stunden (11:59:59,9 vormittags -> 12:00:00,0 nachmittags).
// 12. Uhr anhalten beim Stellen, einfrieren beim Ablesen.
// 13. Wecker: Meldung in ICR Bit 2, wenn Uhr und Weckzeit gleich werden.
// 14. Eingang FLAG: fallende Flanke setzt ICR Bit 4.

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
    reg        tod_tick = 1'b0;
    reg        flag_n   = 1'b1;
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
        .rst      (rst),
        .tick     (en),
        .tod_tick (tod_tick),
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
        .pb_in  (pb_in),
        .flag_n (flag_n)
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

    // n Takte der Netzfrequenz für die Uhr, jeweils einen Takt lang
    task tod_ticks(input integer n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk) tod_tick = 1'b1;
                @(negedge clk) tod_tick = 1'b0;
            end
        end
    endtask

    // Liest die Uhr in der richtigen Reihenfolge (Stunden zuerst, Zehntel
    // zuletzt) und liefert sie als {Stunden, Minuten, Sekunden, Zehntel}.
    reg [31:0] tod_value;

    task read_tod;
        begin
            bus_read(4'hB); tod_value[31:24] = dout;
            bus_read(4'hA); tod_value[23:16] = dout;
            bus_read(4'h9); tod_value[15:8]  = dout;
            bus_read(4'h8); tod_value[7:0]   = dout;
        end
    endtask

    task set_tod(input [7:0] hour, input [7:0] min, input [7:0] sec, input [7:0] tenth);
        begin
            bus_write(4'hB, hour);
            bus_write(4'hA, min);
            bus_write(4'h9, sec);
            bus_write(4'h8, tenth);
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

        // 9. Timer B allein: Startwert 2, fortlaufend
        bus_write(4'hE, 8'h00);         // Timer A aus
        bus_write(4'hD, 8'h7F);         // alle Interrupts sperren
        bus_read(4'hD);                 // alte Meldungen löschen
        bus_write(4'h6, 8'h02);
        bus_write(4'h7, 8'h00);
        bus_write(4'hD, 8'h82);         // Unterlauf Timer B freigeben
        bus_write(4'hF, 8'h11);         // Start + Startwert laden
        wait (irq);
        #1 first_irq = irq_edge;
        idle(1);
        bus_read(4'hD);
        expect_eq(dout, 8'h82, "ICR beim Unterlauf von Timer B");
        wait (irq);
        #1 expect_eq(irq_edge - first_irq, 3, "Schritte zwischen Unterlaeufen B");
        bus_write(4'hF, 8'h00);
        bus_read(4'hD);

        // 10. Timer B zählt Unterläufe von Timer A: A läuft alle 4 Schritte
        //     ab (Startwert 3), B braucht 3 davon (Startwert 2) -> alle 12.
        bus_write(4'h4, 8'h03);
        bus_write(4'h5, 8'h00);
        bus_write(4'h6, 8'h02);
        bus_write(4'h7, 8'h00);
        bus_write(4'hF, 8'h51);         // Start + laden + Quelle Timer A
        bus_write(4'hE, 8'h11);
        wait (irq);
        #1 first_irq = irq_edge;
        idle(1);
        bus_read(4'hD);
        expect_eq(dout & 8'h82, 8'h82, "ICR bei gekoppelten Timern");
        wait (irq);
        #1 expect_eq(irq_edge - first_irq, 12, "Schritte bei gekoppelten Timern");
        bus_write(4'hE, 8'h00);
        bus_write(4'hF, 8'h00);
        bus_write(4'hD, 8'h7F);
        bus_read(4'hD);

        // 11. Uhr mit 50 Hz (CRA Bit 7): 5 Takte = eine Zehntelsekunde
        bus_write(4'hE, 8'h80);
        set_tod(8'h11, 8'h59, 8'h59, 8'h08);            // 11:59:59,8 vormittags
        tod_ticks(4);
        read_tod;
        expect_eq(tod_value, 32'h11595908, "Uhr nach 4 Takten");
        tod_ticks(1);
        read_tod;
        expect_eq(tod_value, 32'h11595909, "Uhr nach 5 Takten");
        tod_ticks(5);
        read_tod;
        expect_eq(tod_value, 32'h92000000, "Uhr nach Uebertrag: 12:00:00,0 nachmittags");
        set_tod(8'h92, 8'h59, 8'h59, 8'h09);            // 12:59:59,9 nachmittags
        tod_ticks(5);
        read_tod;
        expect_eq(tod_value, 32'h81000000, "Uhr: nach 12 kommt 1");
        set_tod(8'h09, 8'h09, 8'h29, 8'h09);
        tod_ticks(5);
        read_tod;
        expect_eq(tod_value, 32'h09093000, "Uhr: BCD-Uebertrag in den Sekunden");

        // 12. Anhalten beim Stellen, Einfrieren beim Ablesen
        bus_write(4'hB, 8'h03);                         // Stunden: Uhr hält an
        tod_ticks(20);
        bus_write(4'hA, 8'h15);
        bus_write(4'h9, 8'h30);
        bus_write(4'h8, 8'h00);                         // Zehntel: Uhr läuft wieder
        read_tod;
        expect_eq(tod_value, 32'h03153000, "Uhr stand waehrend des Stellens");
        bus_read(4'hB);                                 // Stunden lesen: Anzeige friert ein
        tod_ticks(10);                                  // 2 Zehntel vergehen
        bus_read(4'h8);
        expect_eq(dout, 8'h00, "eingefrorene Zehntel");
        bus_read(4'h8);
        expect_eq(dout, 8'h02, "Zehntel nach dem Freigeben");

        // 13. Wecker auf 3:15:30,5
        bus_write(4'hF, 8'h80);                         // Schreiben stellt den Wecker
        set_tod(8'h03, 8'h15, 8'h30, 8'h05);
        bus_write(4'hF, 8'h00);
        bus_write(4'hD, 8'h84);                         // Wecker freigeben
        tod_ticks(10);                                  // Uhr jetzt bei ,4
        expect_eq(irq, 0, "irq vor der Weckzeit");
        tod_ticks(5);
        idle(2);
        expect_eq(irq, 1, "irq zur Weckzeit");
        bus_read(4'hD);
        expect_eq(dout, 8'h84, "ICR zur Weckzeit");
        bus_write(4'hD, 8'h7F);

        // 14. FLAG
        bus_write(4'hD, 8'h90);
        @(negedge clk) flag_n = 1'b0;
        idle(2);
        expect_eq(irq, 1, "irq nach fallender Flanke an FLAG");
        bus_read(4'hD);
        expect_eq(dout, 8'h90, "ICR nach FLAG");
        @(negedge clk) flag_n = 1'b1;
        idle(2);
        expect_eq(irq, 0, "irq nach steigender Flanke an FLAG");

        if (errors == 0) $display("PASS: tb_cia");
        else             $display("FAIL: tb_cia (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: tb_cia Timeout");
        $finish;
    end

endmodule

`default_nettype wire
