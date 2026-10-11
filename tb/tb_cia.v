// tb_cia — Testbench für die CIA 6526 aus MiSTer (mos6526).
// Simulator: Questa
//
// Die CIA hängt direkt an der Testbench. Ein CPU-Takt hat hier 8 Systemtakte;
// phi2_n (Buszugriff) und phi2_p (Timer zählen) kommen wie in soc_c64 je
// einmal pro CPU-Takt. Geprüft wird das Grundverhalten, das der Rechner
// braucht — die Feinheiten des Originals decken die Testsammlungen ab, die
// der Core laut seinem Dateikopf besteht.
// 1. Nach Reset: kein Interrupt, keine Meldung, Ports sind Eingänge.
// 2. Timer A fortlaufend mit Startwert 4: Interrupt alle 5 CPU-Takte; ICR
//    liest $81 und löscht dabei Meldung und Interrupt.
// 3. Einmal-Modus: genau ein Interrupt, danach ist das Startbit 0.
// 4. Timer B zählt Unterläufe von Timer A: A alle 4 Takte, B braucht 3
//    davon, also ein Interrupt alle 12 Takte.
// 5. Uhr: 5 Takte des 50-Hz-Signals ergeben eine Zehntelsekunde, 50 eine
//    Sekunde.
// 6. Ports: Ausgänge liefern das Register, Eingänge liegen auf 1; gelesen
//    wird der Pegel an den Pins.

`timescale 1ns / 1ps
`default_nettype none

module tb_cia;

    reg        clk    = 1'b0;
    reg        rst    = 1'b1;
    reg  [2:0] cyc    = 3'd0;
    reg        cs_n   = 1'b1;
    reg        rw     = 1'b1;
    reg  [3:0] rs     = 4'h0;
    reg  [7:0] db_in  = 8'h00;
    reg  [7:0] pa_in  = 8'hFF;
    reg  [7:0] pb_in  = 8'hFF;
    reg        tod    = 1'b0;
    wire [7:0] db_out;
    wire [7:0] pa_out;
    wire [7:0] pb_out;
    wire       irq_n;

    wire phi2_n = (cyc == 3'd4);
    wire phi2_p = (cyc == 3'd0);

    integer errors     = 0;
    integer cpu_cycle  = 0;     // gezählt bei phi2_p
    integer irq_cycle  = 0;     // CPU-Takt, in dem irq_n zuletzt auf 0 ging
    integer first_irq;

    mos6526 dut (
        .mode    (1'b0),
        .clk     (clk),
        .phi2_p  (phi2_p),
        .phi2_n  (phi2_n),
        .res_n   (~rst),
        .cs_n    (cs_n),
        .rw      (rw),
        .rs      (rs),
        .db_in   (db_in),
        .db_out  (db_out),
        .pa_in   (pa_in),
        .pa_out  (pa_out),
        .pa_oe   (),
        .pb_in   (pb_in),
        .pb_out  (pb_out),
        .pb_oe   (),
        .flag_n  (1'b1),
        .pc_n    (),
        .tod     (tod),
        .sp_in   (1'b1),
        .sp_out  (),
        .cnt_in  (1'b1),
        .cnt_out (),
        .irq_n   (irq_n)
    );

    always #10 clk = ~clk;
    always @(posedge clk) begin
        cyc <= cyc + 3'd1;
        if (phi2_p) cpu_cycle = cpu_cycle + 1;
    end
    always @(negedge irq_n) irq_cycle = cpu_cycle;

    // Buszugriff: cs_n liegt während phi2_n an, wie in soc_c64.
    task bus_write(input [3:0] a, input [7:0] d);
        begin
            // auf den Beginn des Takts mit phi2_n warten; cs_n liegt dann über
            // die Flanke hinweg an, mit der die CIA den Zugriff übernimmt
            wait (cyc == 3'd3); wait (cyc == 3'd4); @(negedge clk);
            cs_n = 1'b0; rw = 1'b0; rs = a; db_in = d;
            @(negedge clk);
            cs_n = 1'b1; rw = 1'b1;
        end
    endtask

    task bus_read(input [3:0] a);       // Ergebnis steht danach in db_out
        begin
            wait (cyc == 3'd3); wait (cyc == 3'd4); @(negedge clk);
            cs_n = 1'b0; rw = 1'b1; rs = a;
            @(negedge clk);
            cs_n = 1'b1;
        end
    endtask

    task idle(input integer n);         // n CPU-Takte warten
        begin
            repeat (n * 8) @(posedge clk);
        end
    endtask

    task tod_ticks(input integer n);    // n Takte des Netzsignals
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk) tod = 1'b1;
                repeat (3) @(negedge clk);
                tod = 1'b0;
                repeat (3) @(negedge clk);
            end
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
        repeat (20) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        idle(2);

        // 1. Reset
        expect_eq(irq_n, 1, "irq_n nach Reset");
        bus_read(4'hD);  expect_eq(db_out, 8'h00, "ICR nach Reset");
        idle(2);
        expect_eq(pa_out, 8'hFF, "pa_out nach Reset");

        // 2. fortlaufender Timer A, Startwert 4
        bus_write(4'h4, 8'h04);
        bus_write(4'h5, 8'h00);
        bus_write(4'hD, 8'h81);         // Unterlauf Timer A freigeben
        bus_write(4'hE, 8'h11);         // Start + Startwert laden
        wait (!irq_n);
        #1 first_irq = irq_cycle;
        bus_read(4'hD);
        expect_eq(db_out, 8'h81, "ICR beim ersten Unterlauf");
        idle(1);
        expect_eq(irq_n, 1, "irq_n nach Lesen von ICR");
        wait (!irq_n);
        #1 expect_eq(irq_cycle - first_irq, 5, "CPU-Takte zwischen Unterlaeufen A");

        // 3. Einmal-Modus
        bus_write(4'hE, 8'h00);
        bus_read(4'hD);
        idle(2);
        bus_write(4'hE, 8'h19);         // Start + laden + einmalig
        wait (!irq_n);
        idle(2);
        bus_read(4'hE);
        expect_eq(db_out & 8'h01, 0, "Startbit nach einmaligem Ablauf");
        bus_read(4'hD);
        expect_eq(db_out, 8'h81, "ICR nach einmaligem Ablauf");
        idle(20);
        expect_eq(irq_n, 1, "kein weiterer Interrupt im Einmal-Modus");

        // 4. Timer B zählt Unterläufe von Timer A
        bus_write(4'hD, 8'h7F);         // alle sperren
        bus_read(4'hD);
        bus_write(4'h4, 8'h03);
        bus_write(4'h5, 8'h00);
        bus_write(4'h6, 8'h02);
        bus_write(4'h7, 8'h00);
        bus_write(4'hD, 8'h82);         // Unterlauf Timer B freigeben
        bus_write(4'hF, 8'h51);         // Start + laden + Quelle Timer A
        bus_write(4'hE, 8'h11);
        wait (!irq_n);
        #1 first_irq = irq_cycle;
        bus_read(4'hD);
        expect_eq(db_out & 8'h82, 8'h82, "ICR bei gekoppelten Timern");
        wait (irq_n);
        wait (!irq_n);
        #1 expect_eq(irq_cycle - first_irq, 12, "CPU-Takte bei gekoppelten Timern");
        bus_write(4'hE, 8'h00);
        bus_write(4'hF, 8'h00);
        bus_write(4'hD, 8'h7F);
        bus_read(4'hD);

        // 5. Uhr mit 50 Hz (CRA Bit 7). Stellen: Stunden zuerst (hält die Uhr
        //    an), Zehntel zuletzt (startet sie). Lesen in derselben Folge.
        bus_write(4'hE, 8'h80);
        bus_write(4'hB, 8'h01);
        bus_write(4'hA, 8'h00);
        bus_write(4'h9, 8'h00);
        bus_write(4'h8, 8'h00);
        tod_ticks(5);
        idle(2);
        bus_read(4'hB);
        bus_read(4'h9);  expect_eq(db_out, 8'h00, "Sekunden nach 5 Netztakten");
        bus_read(4'h8);  expect_eq(db_out, 8'h01, "Zehntel nach 5 Netztakten");
        tod_ticks(45);
        idle(2);
        bus_read(4'hB);  expect_eq(db_out, 8'h01, "Stunden nach 50 Netztakten");
        bus_read(4'h9);  expect_eq(db_out, 8'h01, "Sekunden nach 50 Netztakten");
        bus_read(4'h8);  expect_eq(db_out, 8'h00, "Zehntel nach 50 Netztakten");

        // 6. Ports
        bus_write(4'h2, 8'hFF);
        bus_write(4'h0, 8'hA5);
        idle(2);
        expect_eq(pa_out, 8'hA5, "pa_out als Ausgang");
        bus_write(4'h2, 8'h0F);
        idle(2);
        expect_eq(pa_out, 8'hF5, "pa_out halb Eingang");
        pa_in = 8'h3C;
        bus_read(4'h0);  expect_eq(db_out, 8'h3C, "PRA lesen: Pegel an den Pins");
        pb_in = 8'h7E;
        bus_read(4'h1);  expect_eq(db_out, 8'h7E, "PRB lesen: Pegel an den Pins");
        bus_read(4'h2);  expect_eq(db_out, 8'h0F, "DDRA lesen");

        if (errors == 0) $display("PASS: tb_cia");
        else             $display("FAIL: tb_cia (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: tb_cia Timeout");
        $finish;
    end

endmodule

`default_nettype wire
