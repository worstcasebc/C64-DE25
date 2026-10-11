// pal_test_top — Test-Top-Level: nimmt der Monitor das verdoppelte PAL-Raster?
//
// Zweck:  Vorbereitung für den echten VIC-II (Meilenstein 5). Der VIC-II
//         erzeugt ein PAL-Bild: 504 Pixel pro Zeile, 312 Zeilen, 50 Bilder
//         pro Sekunde. Für HDMI wird jede Zeile und jedes Pixel doppelt
//         ausgegeben. Das ergibt ein Raster, das knapp neben dem genormten
//         576p liegt:
//           1008 Pixel pro Zeile, 624 Zeilen, Pixeltakt 31,5 MHz
//           -> 31,25 kHz Zeilenfrequenz, 50,08 Bilder pro Sekunde
//         Dieses Top-Level zeigt nur Farbbalken in diesem Raster, ohne C64.
//         Zeigt der Monitor sie, kann der VIC-II später genau so ausgeben.
//           SW[0] = 0  sichtbar 768 x 544 (so viel zeigt MiSTer vom C64-Bild)
//           SW[0] = 1  sichtbar 720 x 576 (Bildgröße des genormten 576p)
//           KEY[0]     Reset
//           LEDR[0]    1-Hz-Herzschlag aus dem PLL-Takt — blinkt nur, wenn
//                      die PLL läuft
// Ergebnis (11.10.2026, am Monitor des Entwicklers): Mit 720 x 576 kommt
//         das Bild, der Monitor meldet 720x576 bei 50 Hz. 768 x 544 lehnt
//         er ab ("input timing not supported"). Der VIC-II wird deshalb als
//         720 x 576 ausgegeben, also 360 x 288 C64-Pixel.
// Takte:  clk_sys = 31,5 MHz aus der PLL (4 x Pixeltakt des C64). Der echte
//         PAL-C64 hat 31,528 MHz; mit glatten 31,5 MHz läuft alles 0,09 %
//         langsamer, dafür stimmt die Zeilenfrequenz exakt mit 576p überein.
//         HDMI_TX_CLK ist derselbe Takt um 180 Grad verschoben: Die Daten
//         wechseln mit clk_sys, der Sender übernimmt sie eine halbe Periode
//         später, mitten im gültigen Bereich.
// IP:     pll_c64 (quartus/ip/pll_c64.ip): Eingang 50 MHz, outclk_0 =
//         31,5 MHz mit 0 Grad, outclk_1 = 31,5 MHz mit 180 Grad.
//         reset_release wie im Haupt-Top-Level.
// Quartus: eigene Revision "pal_test" (quartus/pal_test.qsf).

`default_nettype none

module pal_test_top (
    input  wire        CLOCK0_50,
    input  wire [1:0]  KEY,
    input  wire [3:0]  SW,
    output wire [7:0]  LEDR,
    output wire        HDMI_TX_CLK,
    output wire [23:0] HDMI_TX_D,
    output wire        HDMI_TX_DE,
    output wire        HDMI_TX_HS,
    output wire        HDMI_TX_VS,
    output wire        HDMI_I2C_SCL,
    inout  wire        HDMI_I2C_SDA,
    input  wire        HDMI_TX_INT
);

    // --- Reset Release und PLL ----------------------------------------------
    wire ninit_done;

    reset_release u_reset_release (
        .ninit_done (ninit_done)
    );

    wire clk_sys;
    wire clk_sys_180;
    wire pll_locked;

    pll_c64 u_pll_c64 (
        .refclk   (CLOCK0_50),
        .rst      (ninit_done),
        .outclk_0 (clk_sys),
        .outclk_1 (clk_sys_180),
        .locked   (pll_locked)
    );

    // --- Eingänge und Reset -------------------------------------------------
    wire       key0_q;
    wire       sw0_q;
    wire       ninit_done_q;
    wire       pll_locked_q;

    sync_2ff #(.WIDTH(4)) u_sync_in (
        .clk      (clk_sys),
        .d_async  ({pll_locked, ninit_done, ~KEY[0], SW[0]}),
        .d_sync_q ({pll_locked_q, ninit_done_q, key0_q, sw0_q})
    );

    wire rst = key0_q | ninit_done_q | ~pll_locked_q;

    wire heartbeat_q;

    blink #(.HALF_PERIOD(15_750_000)) u_blink (
        .clk   (clk_sys),
        .rst   (rst),
        .led_q (heartbeat_q)
    );

    // --- Zwei Raster mit gleicher Gesamtgröße, verschiedenem Bildausschnitt --
    // A: 768 x 544 sichtbar
    wire [11:0] a_x, a_y;
    wire        a_de, a_hsync, a_vsync;

    video_timing #(
        .H_ACTIVE (768), .H_FP (48), .H_SYNC (96), .H_BP (96),    // 1008
        .V_ACTIVE (544), .V_FP (16), .V_SYNC (6),  .V_BP (58)     // 624
    ) u_timing_a (
        .clk (clk_sys), .rst (rst), .en (1'b1),
        .x_q (a_x), .y_q (a_y), .de (a_de), .hsync (a_hsync), .vsync (a_vsync)
    );

    wire [23:0] a_rgb_q;
    wire        a_de_q, a_hsync_q, a_vsync_q;

    video_colorbars #(.H_ACTIVE(768), .V_ACTIVE(544)) u_bars_a (
        .clk (clk_sys), .en (1'b1),
        .x (a_x), .y (a_y), .de (a_de), .hsync (a_hsync), .vsync (a_vsync),
        .r_q (a_rgb_q[23:16]), .g_q (a_rgb_q[15:8]), .b_q (a_rgb_q[7:0]),
        .de_q (a_de_q), .hsync_q (a_hsync_q), .vsync_q (a_vsync_q)
    );

    // B: 720 x 576 sichtbar
    wire [11:0] b_x, b_y;
    wire        b_de, b_hsync, b_vsync;

    video_timing #(
        .H_ACTIVE (720), .H_FP (72), .H_SYNC (96), .H_BP (120),   // 1008
        .V_ACTIVE (576), .V_FP (8),  .V_SYNC (6),  .V_BP (34)     // 624
    ) u_timing_b (
        .clk (clk_sys), .rst (rst), .en (1'b1),
        .x_q (b_x), .y_q (b_y), .de (b_de), .hsync (b_hsync), .vsync (b_vsync)
    );

    wire [23:0] b_rgb_q;
    wire        b_de_q, b_hsync_q, b_vsync_q;

    video_colorbars #(.H_ACTIVE(720), .V_ACTIVE(576)) u_bars_b (
        .clk (clk_sys), .en (1'b1),
        .x (b_x), .y (b_y), .de (b_de), .hsync (b_hsync), .vsync (b_vsync),
        .r_q (b_rgb_q[23:16]), .g_q (b_rgb_q[15:8]), .b_q (b_rgb_q[7:0]),
        .de_q (b_de_q), .hsync_q (b_hsync_q), .vsync_q (b_vsync_q)
    );

    // --- HDMI ---------------------------------------------------------------
    reg [23:0] hdmi_rgb_q;
    reg        hdmi_de_q;
    reg        hdmi_hsync_q;
    reg        hdmi_vsync_q;

    always @(posedge clk_sys) begin
        hdmi_rgb_q   <= sw0_q ? b_rgb_q   : a_rgb_q;
        hdmi_de_q    <= sw0_q ? b_de_q    : a_de_q;
        hdmi_hsync_q <= sw0_q ? b_hsync_q : a_hsync_q;
        hdmi_vsync_q <= sw0_q ? b_vsync_q : a_vsync_q;
    end

    // 576p arbeitet wie 640x480 mit low-aktiven Sync-Impulsen.
    assign HDMI_TX_CLK = clk_sys_180;
    assign HDMI_TX_D   = hdmi_rgb_q;
    assign HDMI_TX_DE  = hdmi_de_q;
    assign HDMI_TX_HS  = ~hdmi_hsync_q;
    assign HDMI_TX_VS  = ~hdmi_vsync_q;

    // I2C-Konfiguration des HDMI-Senders: 31,5 MHz / (4 * 79) = 100 kHz,
    // Wartezeit 0,2 s.
    wire hdmi_scl_oe_q;
    wire hdmi_sda_oe_q;
    wire hdmi_ready_q;
    wire hdmi_nack_q;

    hdmi_config #(.CLKS_PER_QUARTER(79), .STARTUP_CLKS(6_300_000)) u_hdmi_config (
        .clk      (clk_sys),
        .rst      (rst),
        .int_n    (HDMI_TX_INT),
        .scl_oe_q (hdmi_scl_oe_q),
        .sda_oe_q (hdmi_sda_oe_q),
        .sda_in   (HDMI_I2C_SDA),
        .ready_q  (hdmi_ready_q),
        .nack_q   (hdmi_nack_q)
    );

    assign HDMI_I2C_SCL = ~hdmi_scl_oe_q;
    assign HDMI_I2C_SDA = hdmi_sda_oe_q ? 1'b0 : 1'bz;

    // --- LEDs (low-aktiv): Herzschlag, dazu für diesen Test der HDMI-Zustand -
    //   LEDR[1] HDMI-Sender fertig konfiguriert, LEDR[2] I2C nicht bestätigt
    assign LEDR = ~{5'b0, hdmi_nack_q, hdmi_ready_q, heartbeat_q};

endmodule

`default_nettype wire
