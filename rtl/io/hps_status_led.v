// hps_status_led — Zustandsanzeige: Läuft der Dienst unter Linux?
//
// Zweck:  Das FPGA ist nach dem Einschalten sofort da, Linux braucht noch
//         eine Weile — so lange gehen Tastatur, Laufwerk und Menü nicht.
//         Eine LED soll das zeigen:
//           blinkt schnell   der Dienst unter Linux meldet sich nicht
//                            (Linux bootet noch, oder der Dienst ist aus)
//           leuchtet         der Dienst läuft, alles in Ordnung
//           blinkt langsam   der Dienst läuft und meldet ein Problem
//         "Läuft" wird nicht mit einem Bit gemerkt, das der Dienst setzt
//         und wieder löscht — ein abgestürzter Dienst könnte es nicht mehr
//         löschen. Stattdessen muss er sich regelmäßig melden, wie ein
//         Nachtwächter an der Stechuhr: Bleibt die Meldung länger als
//         TIMEOUT Takte aus, gilt er als weg. Zwei weitere Bits, die er
//         mitschickt, gelten nur, solange er lebt.
// Takt:   clk (der Takt der Brücke, 100 MHz), synchroner Reset rst (aktiv
//         high). Die Ausgänge gehen an LEDs, also nur fürs Auge.
// Ports:  wr = 1 für einen Takt: Lebenszeichen, dazu wr_data:
//           Bit 0 = 1: Problem (LED blinkt langsam statt zu leuchten)
//           Bit 1    : frei verfügbare zweite LED (aux_q)
//         alive_q = 1, solange Lebenszeichen kommen.
//         led_q — die Zustands-LED, 1 = an. aux_q — Bit 1 des letzten
//         Lebenszeichens, 0, wenn der Dienst weg ist.
// Zeiten: FAST_HALF und SLOW_HALF sind die halben Blinkperioden in Takten
//         (Default 8 Hz und 1 Hz), TIMEOUT die Frist (Default 3 s).

`default_nettype none

module hps_status_led #(
    parameter CLK_HZ    = 100_000_000,
    parameter FAST_HALF = CLK_HZ / 16,
    parameter SLOW_HALF = CLK_HZ / 2,
    parameter TIMEOUT   = 3 * CLK_HZ
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       wr,
    input  wire [1:0] wr_data,
    output reg        alive_q,
    output reg        led_q,
    output wire       aux_q
);

    localparam DIV_W = $clog2(SLOW_HALF + 1);
    localparam TO_W  = $clog2(TIMEOUT + 1);

    reg [DIV_W-1:0] fast_cnt_q;
    reg [DIV_W-1:0] slow_cnt_q;
    reg             fast_q;         // Blinktakte
    reg             slow_q;
    reg [TO_W-1:0]  timeout_q;      // Takte seit dem letzten Lebenszeichen
    reg             problem_q;
    reg             aux_bit_q;

    assign aux_q = alive_q & aux_bit_q;

    always @(posedge clk) begin
        if (rst) begin
            fast_cnt_q <= {DIV_W{1'b0}};
            slow_cnt_q <= {DIV_W{1'b0}};
            fast_q     <= 1'b0;
            slow_q     <= 1'b0;
            timeout_q  <= {TO_W{1'b0}};
            alive_q    <= 1'b0;
            problem_q  <= 1'b0;
            aux_bit_q  <= 1'b0;
            led_q      <= 1'b0;
        end else begin
            // Blinktakte laufen immer durch
            if (fast_cnt_q == FAST_HALF - 1) begin
                fast_cnt_q <= {DIV_W{1'b0}};
                fast_q     <= ~fast_q;
            end else begin
                fast_cnt_q <= fast_cnt_q + 1'b1;
            end
            if (slow_cnt_q == SLOW_HALF - 1) begin
                slow_cnt_q <= {DIV_W{1'b0}};
                slow_q     <= ~slow_q;
            end else begin
                slow_cnt_q <= slow_cnt_q + 1'b1;
            end

            // Stechuhr
            if (wr) begin
                alive_q   <= 1'b1;
                timeout_q <= {TO_W{1'b0}};
                problem_q <= wr_data[0];
                aux_bit_q <= wr_data[1];
            end else if (timeout_q == TIMEOUT - 1) begin
                alive_q <= 1'b0;
            end else begin
                timeout_q <= timeout_q + 1'b1;
            end

            led_q <= !alive_q ? fast_q : (problem_q ? slow_q : 1'b1);
        end
    end

endmodule

`default_nettype wire
