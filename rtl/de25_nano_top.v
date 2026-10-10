// de25_nano_top — Top-Level für Meilenstein 1, Schritt 1 (Blinky).
//
// Zweck:  Erster Board-Test: Takt, Reset, Taster, Schalter und LEDs.
//           LEDR[0]   1-Hz-Herzschlag (zeigt: Takt läuft, Design ist geladen)
//           LEDR[4:1] Schalter SW[3:0]
//           LEDR[5]   KEY1 gedrückt
//           LEDR[6]   unbenutzt (aus)
//           LEDR[7]   Reset aktiv (KEY0 gedrückt)
// Takt:   CLOCK0_50 (50 MHz) als einzige Domäne clk_50.
// Ports:  Namen wie im Terasic-Handbuch (Großschreibung nur hier im Top-Level).
//         KEY und LEDR sind low-aktiv; intern wird alles high-aktiv geführt.

`default_nettype none

module de25_nano_top #(
    parameter BLINK_HALF_PERIOD = 25_000_000   // 0,5 s bei 50 MHz
) (
    input  wire       CLOCK0_50,
    input  wire [1:0] KEY,
    input  wire [3:0] SW,
    output wire [7:0] LEDR
);

    wire clk_50 = CLOCK0_50;

    // Taster/Schalter in die Taktdomäne holen (Taster dabei high-aktiv machen).
    wire [1:0] key_q;
    wire [3:0] sw_q;

    sync_2ff #(.WIDTH(2)) u_sync_key (
        .clk      (clk_50),
        .d_async  (~KEY),
        .d_sync_q (key_q)
    );

    sync_2ff #(.WIDTH(4)) u_sync_sw (
        .clk      (clk_50),
        .d_async  (SW),
        .d_sync_q (sw_q)
    );

    wire rst = key_q[0];

    wire heartbeat_q;

    blink #(.HALF_PERIOD(BLINK_HALF_PERIOD)) u_blink (
        .clk   (clk_50),
        .rst   (rst),
        .led_q (heartbeat_q)
    );

    // Interne Sicht: 1 = LED an.
    wire [7:0] led = {rst, 1'b0, key_q[1], sw_q, heartbeat_q};

    assign LEDR = ~led;

endmodule

`default_nettype wire
