// cia — CIA 6526: zwei 8-Bit-Ports, zwei Timer, Uhr und Interrupts.
//
// Zweck:  Die CIA ist der "Hausmeister" des C64: Sie fragt die Tastatur ab
//         und weckt die CPU in festen Abständen per Interrupt. Das KERNAL
//         lässt Timer A der ersten CIA rund 60-mal pro Sekunde ablaufen und
//         erledigt in jedem Interrupt Uhr, Cursor-Blinken und
//         Tastaturabfrage. Register (Adresse = untere 4 Bit, alle 16
//         wiederholt):
//           $0 PRA, $1 PRB    Port-Daten
//           $2 DDRA, $3 DDRB  Richtung, Bit = 1 heißt Ausgang
//           $4, $5            Timer A: lesen = Zählerstand,
//           $6, $7            Timer B: schreiben = Startwert (Latch)
//           $8-$B             Uhr (TOD): Zehntel, Sekunden, Minuten,
//                             Stunden — als BCD-Ziffern, Stunden 1-12 mit
//                             Bit 7 = nachmittags
//           $C SDR            serielles Schieberegister (nur Speicher)
//           $D ICR            Interrupts: lesen = was ist passiert (und
//                             löschen), schreiben = was darf den Interrupt
//                             auslösen. Bit 0 Timer A, 1 Timer B, 2 Wecker,
//                             4 Eingang FLAG
//           $E CRA, $F CRB    Timer steuern: Bit 0 Start, Bit 3 einmalig
//                             statt fortlaufend, Bit 4 Startwert laden.
//                             CRA Bit 7: Uhrentakt 50 statt 60 Hz.
//                             CRB Bit 6: Timer B zählt Unterläufe von
//                             Timer A statt CPU-Takte. CRB Bit 7: Schreiben
//                             auf $8-$B stellt den Wecker statt der Uhr.
//         Ein Timer zählt um 1 herunter; bei 0 lädt er den Startwert neu
//         und meldet einen Unterlauf. Eine Periode dauert also
//         Startwert + 1 Zählschritte.
//         Die Uhr hält beim Schreiben der Stunden an, bis die Zehntel
//         geschrieben sind; beim Lesen der Stunden bleibt die Anzeige
//         stehen, bis die Zehntel gelesen sind. So lässt sich die Zeit
//         stellen und ablesen, ohne dass sie dazwischen weiterspringt.
// Takt:   clk, synchroner Reset rst (aktiv high).
//         tick = 1: ein CPU-Takt ist vergangen, die Timer zählen. Das
//         geschieht auch, wenn die CPU gerade angehalten ist (der VIC-II
//         hält nur die CPU an, nicht die Zeit).
//         tod_tick = 1: ein Takt der Netzfrequenz (50 oder 60 Hz) für die
//         Uhr.
//         en = 1: die CPU greift in diesem Takt auf den Bus zu.
// Bus:    sel = 1 bei der Adresse der CIA. Lesedaten liegen wie beim RAM
//         einen Schritt später an dout_q an.
// Ports:  irq = 1, solange ein freigegebenes Ereignis ansteht.
//         pa_out/pb_out — Pegel, die die CIA ausgibt (Eingangsleitungen: 1).
//         pa_in/pb_in — Pegel an den Pins, synchron zu clk.
//         flag_n — Eingang FLAG; eine fallende Flanke setzt ICR Bit 4.
// Fehlt:  Die Leitungen CNT, SP und PC sowie die Ausgabe der Timer auf
//         PB6/PB7. Timer mit Zählquelle CNT stehen still, das
//         Schieberegister überträgt nichts. Das Zeitverhalten der Timer ist
//         nicht taktgenau wie beim Original (dort wirken Start und Laden
//         ein bis zwei Takte verzögert). Nach Reset läuft die Uhr ab
//         1:00:00,0 Uhr.

`default_nettype none

module cia (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick,
    input  wire       tod_tick,
    input  wire       en,
    input  wire       sel,
    input  wire       we,
    input  wire [3:0] addr,
    input  wire [7:0] din,
    output reg  [7:0] dout_q,
    output wire       irq,
    output wire [7:0] pa_out,
    output wire [7:0] pb_out,
    input  wire [7:0] pa_in,
    input  wire [7:0] pb_in,
    input  wire       flag_n
);

    localparam [3:0] REG_PRA  = 4'h0, REG_PRB  = 4'h1, REG_DDRA = 4'h2, REG_DDRB = 4'h3,
                     REG_TALO = 4'h4, REG_TAHI = 4'h5, REG_TBLO = 4'h6, REG_TBHI = 4'h7,
                     REG_TENTH = 4'h8, REG_SEC = 4'h9, REG_MIN  = 4'hA, REG_HOUR = 4'hB,
                     REG_SDR  = 4'hC, REG_ICR  = 4'hD, REG_CRA  = 4'hE, REG_CRB  = 4'hF;

    reg [7:0]  pra_q;
    reg [7:0]  prb_q;
    reg [7:0]  ddra_q;
    reg [7:0]  ddrb_q;
    reg [7:0]  sdr_q;
    reg [15:0] ta_latch_q;      // Startwert Timer A
    reg [15:0] ta_q;            // Zählerstand Timer A
    reg [15:0] tb_latch_q;
    reg [15:0] tb_q;
    reg [7:0]  cra_q;           // Bit 4 wird nicht gespeichert
    reg [7:0]  crb_q;
    reg [4:0]  icr_flag_q;
    reg [4:0]  icr_mask_q;
    reg        flag_n_q;

    // --- Timer --------------------------------------------------------------
    wire ta_start     = cra_q[0];
    wire ta_oneshot   = cra_q[3];
    wire ta_count     = tick && ta_start && !cra_q[5];      // Bit 5 = 1: CNT, steht still
    wire ta_underflow = ta_count && (ta_q == 16'd0);

    wire tb_start     = crb_q[0];
    wire tb_oneshot   = crb_q[3];
    wire tb_source    = crb_q[6] ? ta_underflow             // Unterläufe von Timer A
                                 : tick && !crb_q[5];       // CPU-Takte (Bit 5 = 1: CNT)
    wire tb_count     = tb_start && tb_source;
    wire tb_underflow = tb_count && (tb_q == 16'd0);

    // --- Uhr (TOD) ----------------------------------------------------------
    reg [3:0] tod_tenth_q;      // 0-9
    reg [6:0] tod_sec_q;        // BCD 00-59
    reg [6:0] tod_min_q;        // BCD 00-59
    reg [4:0] tod_hour_q;       // BCD 01-12
    reg       tod_pm_q;
    reg       tod_run_q;        // 0: angehalten (zwischen Schreiben von Stunden und Zehnteln)
    reg [2:0] tod_div_q;        // teilt den Netztakt auf Zehntelsekunden
    reg [3:0] alarm_tenth_q;
    reg [6:0] alarm_sec_q;
    reg [6:0] alarm_min_q;
    reg [4:0] alarm_hour_q;
    reg       alarm_pm_q;
    reg       tod_latched_q;    // Anzeige eingefroren (zwischen Lesen von Stunden und Zehnteln)
    reg [3:0] show_tenth_q;
    reg [6:0] show_sec_q;
    reg [6:0] show_min_q;
    reg [4:0] show_hour_q;
    reg       show_pm_q;
    reg       alarm_match_q;

    wire tod_step = tod_tick && tod_run_q && (tod_div_q == (cra_q[7] ? 3'd4 : 3'd5));

    wire alarm_match = (tod_tenth_q == alarm_tenth_q) && (tod_sec_q == alarm_sec_q) &&
                       (tod_min_q == alarm_min_q) && (tod_hour_q == alarm_hour_q) &&
                       (tod_pm_q == alarm_pm_q);

    // Zählt eine zweistellige BCD-Zahl 00-59 um 1 weiter.
    function [6:0] bcd60_next(input [6:0] value);
        if (value[3:0] != 4'd9) bcd60_next = value + 7'd1;
        else if (value[6:4] != 3'd5) bcd60_next = {value[6:4] + 3'd1, 4'd0};
        else bcd60_next = 7'd0;
    endfunction

    wire write = en && sel && we;
    wire read  = en && sel && !we;

    assign irq    = |(icr_flag_q & icr_mask_q);
    assign pa_out = pra_q | ~ddra_q;
    assign pb_out = prb_q | ~ddrb_q;

    always @(posedge clk) begin
        if (rst) begin
            pra_q         <= 8'h00;
            prb_q         <= 8'h00;
            ddra_q        <= 8'h00;
            ddrb_q        <= 8'h00;
            sdr_q         <= 8'h00;
            ta_latch_q    <= 16'hFFFF;
            ta_q          <= 16'hFFFF;
            tb_latch_q    <= 16'hFFFF;
            tb_q          <= 16'hFFFF;
            cra_q         <= 8'h00;
            crb_q         <= 8'h00;
            icr_flag_q    <= 5'b0;
            icr_mask_q    <= 5'b0;
            flag_n_q      <= 1'b1;
            tod_tenth_q   <= 4'd0;
            tod_sec_q     <= 7'h00;
            tod_min_q     <= 7'h00;
            tod_hour_q    <= 5'h01;
            tod_pm_q      <= 1'b0;
            tod_run_q     <= 1'b1;
            tod_div_q     <= 3'd0;
            alarm_tenth_q <= 4'd0;
            alarm_sec_q   <= 7'h00;
            alarm_min_q   <= 7'h00;
            alarm_hour_q  <= 5'h00;
            alarm_pm_q    <= 1'b0;
            tod_latched_q <= 1'b0;
            alarm_match_q <= 1'b0;
        end else begin
            // Timer zählen
            if (ta_count) ta_q <= ta_underflow ? ta_latch_q : ta_q - 1'b1;
            if (ta_underflow && ta_oneshot) cra_q[0] <= 1'b0;
            if (tb_count) tb_q <= tb_underflow ? tb_latch_q : tb_q - 1'b1;
            if (tb_underflow && tb_oneshot) crb_q[0] <= 1'b0;

            // Uhr zählen
            if (tod_tick && tod_run_q) tod_div_q <= tod_step ? 3'd0 : tod_div_q + 1'b1;
            if (tod_step) begin
                if (tod_tenth_q != 4'd9) begin
                    tod_tenth_q <= tod_tenth_q + 1'b1;
                end else begin
                    tod_tenth_q <= 4'd0;
                    tod_sec_q   <= bcd60_next(tod_sec_q);
                    if (tod_sec_q == 7'h59) begin
                        tod_min_q <= bcd60_next(tod_min_q);
                        if (tod_min_q == 7'h59) begin
                            // 11 -> 12 wechselt vor-/nachmittags, 12 -> 1
                            if      (tod_hour_q == 5'h12) tod_hour_q <= 5'h01;
                            else if (tod_hour_q == 5'h09) tod_hour_q <= 5'h10;
                            else                          tod_hour_q <= tod_hour_q + 1'b1;
                            if (tod_hour_q == 5'h11) tod_pm_q <= ~tod_pm_q;
                        end
                    end
                end
            end

            // Meldungen. Lesen von ICR löscht sie; eine neue im selben Takt
            // bleibt erhalten.
            flag_n_q      <= flag_n;
            alarm_match_q <= alarm_match;
            if (read && addr == REG_ICR) icr_flag_q <= 5'b0;
            if (ta_underflow)                  icr_flag_q[0] <= 1'b1;
            if (tb_underflow)                  icr_flag_q[1] <= 1'b1;
            if (alarm_match && !alarm_match_q) icr_flag_q[2] <= 1'b1;
            if (flag_n_q && !flag_n)           icr_flag_q[4] <= 1'b1;

            // Lesen der Uhr: Stunden frieren die Anzeige ein, Zehntel geben
            // sie wieder frei.
            if (read && addr == REG_HOUR && !tod_latched_q) begin
                tod_latched_q <= 1'b1;
                show_tenth_q  <= tod_tenth_q;
                show_sec_q    <= tod_sec_q;
                show_min_q    <= tod_min_q;
                show_hour_q   <= tod_hour_q;
                show_pm_q     <= tod_pm_q;
            end
            if (read && addr == REG_TENTH) tod_latched_q <= 1'b0;

            // Schreibzugriffe (haben Vorrang vor dem Zählen)
            if (write) begin
                case (addr)
                    REG_PRA:  pra_q  <= din;
                    REG_PRB:  prb_q  <= din;
                    REG_DDRA: ddra_q <= din;
                    REG_DDRB: ddrb_q <= din;
                    REG_TALO: ta_latch_q[7:0] <= din;
                    REG_TAHI: begin
                        ta_latch_q[15:8] <= din;
                        // Steht der Timer, wird der Startwert sofort geladen.
                        if (!ta_start) ta_q <= {din, ta_latch_q[7:0]};
                    end
                    REG_TBLO: tb_latch_q[7:0] <= din;
                    REG_TBHI: begin
                        tb_latch_q[15:8] <= din;
                        if (!tb_start) tb_q <= {din, tb_latch_q[7:0]};
                    end
                    REG_TENTH: begin
                        if (crb_q[7]) begin
                            alarm_tenth_q <= din[3:0];
                        end else begin
                            tod_tenth_q <= din[3:0];
                            tod_run_q   <= 1'b1;
                            tod_div_q   <= 3'd0;
                        end
                    end
                    REG_SEC: begin
                        if (crb_q[7]) alarm_sec_q <= din[6:0];
                        else          tod_sec_q   <= din[6:0];
                    end
                    REG_MIN: begin
                        if (crb_q[7]) alarm_min_q <= din[6:0];
                        else          tod_min_q   <= din[6:0];
                    end
                    REG_HOUR: begin
                        if (crb_q[7]) begin
                            alarm_hour_q <= din[4:0];
                            alarm_pm_q   <= din[7];
                        end else begin
                            tod_hour_q <= din[4:0];
                            tod_pm_q   <= din[7];
                            tod_run_q  <= 1'b0;
                        end
                    end
                    REG_SDR: sdr_q <= din;
                    REG_ICR: begin
                        // Bit 7 = 1: genannte Ereignisse freigeben, 0: sperren
                        if (din[7]) icr_mask_q <= icr_mask_q |  din[4:0];
                        else        icr_mask_q <= icr_mask_q & ~din[4:0];
                    end
                    REG_CRA: begin
                        cra_q <= {din[7:5], 1'b0, din[3:0]};
                        if (din[4]) ta_q <= ta_latch_q;
                    end
                    REG_CRB: begin
                        crb_q <= {din[7:5], 1'b0, din[3:0]};
                        if (din[4]) tb_q <= tb_latch_q;
                    end
                endcase
            end
        end
    end

    // Lesen: Bei den Ports zählt für Ausgänge das Register, für Eingänge
    // der Pegel am Pin. Die Uhr zeigt die eingefrorene Anzeige, falls es
    // eine gibt.
    always @(posedge clk) begin
        if (en) begin
            case (addr)
                REG_PRA:   dout_q <= (pra_q & ddra_q) | (pa_in & ~ddra_q);
                REG_PRB:   dout_q <= (prb_q & ddrb_q) | (pb_in & ~ddrb_q);
                REG_DDRA:  dout_q <= ddra_q;
                REG_DDRB:  dout_q <= ddrb_q;
                REG_TALO:  dout_q <= ta_q[7:0];
                REG_TAHI:  dout_q <= ta_q[15:8];
                REG_TBLO:  dout_q <= tb_q[7:0];
                REG_TBHI:  dout_q <= tb_q[15:8];
                REG_TENTH: dout_q <= {4'h0, tod_latched_q ? show_tenth_q : tod_tenth_q};
                REG_SEC:   dout_q <= {1'b0, tod_latched_q ? show_sec_q : tod_sec_q};
                REG_MIN:   dout_q <= {1'b0, tod_latched_q ? show_min_q : tod_min_q};
                REG_HOUR:  dout_q <= tod_latched_q ? {show_pm_q, 2'b00, show_hour_q}
                                                   : {tod_pm_q,  2'b00, tod_hour_q};
                REG_SDR:   dout_q <= sdr_q;
                REG_ICR:   dout_q <= {irq, 2'b00, icr_flag_q};
                REG_CRA:   dout_q <= cra_q;
                REG_CRB:   dout_q <= crb_q;
            endcase
        end
    end

endmodule

`default_nettype wire
