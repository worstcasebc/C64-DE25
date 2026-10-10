// de25_nano_top — Top-Level für Meilenstein 1, Schritt 2 (PLL + Reset Release).
//
// Zweck:  Board-Test für Takt, Reset, PLL, Taster, Schalter und LEDs.
//           LEDR[0]   1-Hz-Herzschlag aus clk_50  (Boardtakt)
//           LEDR[4:1] Schalter SW[3:0]
//           LEDR[5]   KEY1 gedrückt
//           LEDR[6]   2-Hz-Herzschlag aus clk_100 (PLL) — blinkt nur, wenn
//                     die PLL eingerastet ist
//           LEDR[7]   Reset aktiv (KEY0 gedrückt)
// Takte:  clk_50  = CLOCK0_50 (50 MHz, Boardoszillator)
//         clk_100 = PLL-Ausgang (100 MHz, aus clk_50 abgeleitet)
//         Übergänge zwischen den Domänen nur über sync_2ff.
// Ports:  Namen wie im Terasic-Handbuch (Großschreibung nur hier im Top-Level).
//         KEY und LEDR sind low-aktiv; intern wird alles high-aktiv geführt.
// IP:     pll_sys und reset_release sind Intel-IP (quartus/ip/*.ip) und in
//         Icarus nicht simulierbar — deshalb bleibt hier nur Verdrahtung.

`default_nettype none

module de25_nano_top #(
    parameter BLINK_HALF_PERIOD = 25_000_000   // Takte pro halber Blinkperiode
) (
    input  wire       CLOCK0_50,
    input  wire [1:0] KEY,
    input  wire [3:0] SW,
    output wire [7:0] LEDR
);

    wire clk_50 = CLOCK0_50;

    // --- Reset Release: 1, solange das FPGA noch konfiguriert wird ----------
    wire ninit_done;

    reset_release u_reset_release (
        .ninit_done (ninit_done)
    );

    // --- PLL: 50 MHz -> 100 MHz ---------------------------------------------
    wire clk_100;
    wire pll_locked;

    pll_sys u_pll_sys (
        .refclk   (clk_50),
        .rst      (ninit_done),
        .outclk_0 (clk_100),
        .locked   (pll_locked)
    );

    // --- Domäne clk_50 ------------------------------------------------------
    // Taster/Schalter/ninit_done in die Taktdomäne holen (Taster high-aktiv).
    wire [1:0] key_q;
    wire [3:0] sw_q;
    wire       ninit_done_q;

    sync_2ff #(.WIDTH(3)) u_sync_key (
        .clk      (clk_50),
        .d_async  ({ninit_done, ~KEY}),
        .d_sync_q ({ninit_done_q, key_q})
    );

    sync_2ff #(.WIDTH(4)) u_sync_sw (
        .clk      (clk_50),
        .d_async  (SW),
        .d_sync_q (sw_q)
    );

    wire rst = key_q[0] | ninit_done_q;

    wire heartbeat_50_q;

    blink #(.HALF_PERIOD(BLINK_HALF_PERIOD)) u_blink_50 (
        .clk   (clk_50),
        .rst   (rst),
        .led_q (heartbeat_50_q)
    );

    // --- Domäne clk_100 -----------------------------------------------------
    // Eigener Reset: aktiv, solange rst anliegt oder die PLL nicht eingerastet ist.
    wire rst_sync_100_q;
    wire pll_locked_100_q;

    sync_2ff #(.WIDTH(2)) u_sync_rst_100 (
        .clk      (clk_100),
        .d_async  ({rst, pll_locked}),
        .d_sync_q ({rst_sync_100_q, pll_locked_100_q})
    );

    wire rst_100 = rst_sync_100_q | ~pll_locked_100_q;

    wire heartbeat_100_q;

    blink #(.HALF_PERIOD(BLINK_HALF_PERIOD)) u_blink_100 (
        .clk   (clk_100),
        .rst   (rst_100),
        .led_q (heartbeat_100_q)
    );

    // --- LEDs ---------------------------------------------------------------
    // Interne Sicht: 1 = LED an. LEDs dürfen direkt aus beiden Domänen kommen,
    // weil sie nur das Auge erreichen und keine weitere Logik.
    wire [7:0] led = {rst, heartbeat_100_q, key_q[1], sw_q, heartbeat_50_q};

    assign LEDR = ~led;

endmodule

`default_nettype wire
