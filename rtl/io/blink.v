// blink — Blinksignal per Taktzähler ("Herzschlag").
//
// Zweck:  Teilt den Takt herunter: Nach jeweils HALF_PERIOD Takten wird der
//         Ausgang umgeschaltet. Blinkfrequenz = f_clk / (2 * HALF_PERIOD).
//         Default: 50 MHz / (2 * 25_000_000) = 1 Hz.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high).
// Ports:  led_q — Blinkausgang (aktiv high; Invertierung für die
//         low-aktiven Board-LEDs passiert im Top-Level).

`default_nettype none

module blink #(
    parameter HALF_PERIOD = 25_000_000   // Takte pro halber Blinkperiode
) (
    input  wire clk,
    input  wire rst,
    output reg  led_q
);

    // Zählerbreite passend zum Endwert (mindestens 1 Bit).
    localparam CNT_W = (HALF_PERIOD > 1) ? $clog2(HALF_PERIOD) : 1;

    reg [CNT_W-1:0] cnt_q;

    always @(posedge clk) begin
        if (rst) begin
            cnt_q <= {CNT_W{1'b0}};
            led_q <= 1'b0;
        end else if (cnt_q == HALF_PERIOD - 1) begin
            cnt_q <= {CNT_W{1'b0}};
            led_q <= ~led_q;
        end else begin
            cnt_q <= cnt_q + 1'b1;
        end
    end

endmodule

`default_nettype wire
