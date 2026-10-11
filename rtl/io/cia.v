// cia — vereinfachte CIA 6526: zwei 8-Bit-Ports, Timer A und Interrupts.
//
// Zweck:  Die CIA ist der "Hausmeister" des C64: Sie fragt die Tastatur ab
//         und weckt die CPU in festen Abständen per Interrupt (IRQ). Das
//         KERNAL lässt Timer A rund 60-mal pro Sekunde ablaufen und erledigt
//         in jedem Interrupt Uhr, Cursor-Blinken und Tastaturabfrage.
//         Vorhandene Register (Adresse = untere 4 Bit, alle 16 wiederholt):
//           $0 PRA, $1 PRB    Port-Daten
//           $2 DDRA, $3 DDRB  Richtung, Bit = 1 heißt Ausgang
//           $4, $5            Timer A: lesen = Zählerstand,
//                             schreiben = Startwert (Latch)
//           $D ICR            Interrupts: lesen = was ist passiert (und
//                             löschen), schreiben = was darf IRQ auslösen
//           $E CRA            Timer A steuern: Bit 0 Start, Bit 3 einmalig
//                             statt fortlaufend, Bit 4 Startwert laden
//         Timer A zählt in jedem CPU-Schritt um 1 herunter. Bei 0 lädt er
//         den Startwert neu und meldet einen Unterlauf; eine Periode dauert
//         also Startwert + 1 Schritte.
// Takt:   clk, synchroner Reset rst (aktiv high).
//         tick = 1: ein CPU-Takt ist vergangen, der Timer zählt. Das
//         geschieht auch, wenn die CPU gerade angehalten ist (der VIC-II
//         hält nur die CPU an, nicht die Zeit).
//         en = 1: die CPU greift in diesem Takt auf den Bus zu.
// Bus:    sel = 1 bei der Adresse der CIA. Lesedaten liegen wie beim RAM
//         einen Schritt später an dout_q an.
// Ports:  irq = 1, solange ein freigegebenes Ereignis ansteht.
//         pa_out/pb_out — Pegel, die die CIA ausgibt (Eingangsleitungen: 1).
//         pa_in/pb_in — Pegel an den Pins, synchron zu clk.
// Fehlt noch: Timer B, Uhr (TOD), serielles Schieberegister, die Leitungen
//         CNT/FLAG/PC. Die zugehörigen Register lesen $00. Das Zeitverhalten
//         des Timers ist nicht taktgenau wie beim Original.

`default_nettype none

module cia (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick,
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
    input  wire [7:0] pb_in
);

    localparam [3:0] REG_PRA  = 4'h0, REG_PRB  = 4'h1, REG_DDRA = 4'h2, REG_DDRB = 4'h3,
                     REG_TALO = 4'h4, REG_TAHI = 4'h5, REG_ICR  = 4'hD, REG_CRA  = 4'hE;

    reg [7:0]  pra_q;
    reg [7:0]  prb_q;
    reg [7:0]  ddra_q;
    reg [7:0]  ddrb_q;
    reg [15:0] ta_latch_q;      // Startwert
    reg [15:0] ta_q;            // Zählerstand
    reg [7:0]  cra_q;           // Bit 4 wird nicht gespeichert
    reg [4:0]  icr_flag_q;      // Bit 0: Unterlauf Timer A
    reg [4:0]  icr_mask_q;

    wire ta_start     = cra_q[0];
    wire ta_oneshot   = cra_q[3];
    wire ta_underflow = ta_start && (ta_q == 16'd0);

    wire write = en && sel && we;
    wire read  = en && sel && !we;

    assign irq    = |(icr_flag_q & icr_mask_q);
    assign pa_out = pra_q | ~ddra_q;
    assign pb_out = prb_q | ~ddrb_q;

    always @(posedge clk) begin
        if (rst) begin
            pra_q      <= 8'h00;
            prb_q      <= 8'h00;
            ddra_q     <= 8'h00;
            ddrb_q     <= 8'h00;
            ta_latch_q <= 16'hFFFF;
            ta_q       <= 16'hFFFF;
            cra_q      <= 8'h00;
            icr_flag_q <= 5'b0;
            icr_mask_q <= 5'b0;
        end else begin
            // Timer A zählen
            if (tick) begin
                if (ta_start) ta_q <= ta_underflow ? ta_latch_q : ta_q - 1'b1;
                if (ta_underflow && ta_oneshot) cra_q[0] <= 1'b0;
            end

            // Lesen von ICR löscht die Meldungen; eine neue im selben
            // Takt bleibt erhalten.
            if (read && addr == REG_ICR) icr_flag_q <= 5'b0;
            if (tick && ta_underflow) icr_flag_q[0] <= 1'b1;

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
                    REG_ICR: begin
                        // Bit 7 = 1: genannte Ereignisse freigeben, 0: sperren
                        if (din[7]) icr_mask_q <= icr_mask_q |  din[4:0];
                        else        icr_mask_q <= icr_mask_q & ~din[4:0];
                    end
                    REG_CRA: begin
                        cra_q <= {din[7:5], 1'b0, din[3:0]};
                        if (din[4]) ta_q <= ta_latch_q;
                    end
                    default: ;
                endcase
            end
        end
    end

    // Lesen: Bei den Ports zählt für Ausgänge das Register, für Eingänge
    // der Pegel am Pin.
    always @(posedge clk) begin
        if (en) begin
            case (addr)
                REG_PRA:  dout_q <= (pra_q & ddra_q) | (pa_in & ~ddra_q);
                REG_PRB:  dout_q <= (prb_q & ddrb_q) | (pb_in & ~ddrb_q);
                REG_DDRA: dout_q <= ddra_q;
                REG_DDRB: dout_q <= ddrb_q;
                REG_TALO: dout_q <= ta_q[7:0];
                REG_TAHI: dout_q <= ta_q[15:8];
                REG_ICR:  dout_q <= {irq, 2'b00, icr_flag_q};
                REG_CRA:  dout_q <= cra_q;
                default:  dout_q <= 8'h00;
            endcase
        end
    end

endmodule

`default_nettype wire
