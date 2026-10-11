// de25_nano_top — Top-Level, Stand Meilenstein 5 (echter VIC-II über HDMI).
//
// Zweck:  Verdrahtet den C64-Rechner mit dem Board.
//           KEY[0]    Reset
//           SW[0]     1 zeigt statt des C64-Bildes das Testbild mit
//                     Farbbalken
//           LEDR[0]   1-Hz-Herzschlag aus clk_sys — blinkt nur, wenn die
//                     PLL läuft
//           LEDR[7:1] aus. Zum Fehlersuchen stehen intern Signale bereit,
//                     siehe unten in "LEDs".
//           FPGA_UART_TX  Textausgabe des 6502-Programms, 115200 Baud 8N1,
//                     über den FTDI-Chip am Type-C-Anschluss
//           FPGA_UART_RX  Tastatur-Ersatz: Zeichen aus dem Terminal werden
//                     auf der C64-Tastatur getippt (ascii_key_typer);
//                     Ladeblöcke gehen direkt ins RAM (prg_loader)
//           HDMI      Bild des VIC-II, zeilenverdoppelt (video_scandoubler):
//                     720 x 576 bei 50 Hz über den HDMI-Sender ADV7513
// Takte:  clk_sys = 31,5 MHz aus der PLL, die einzige Domäne. Das ist das
//         Vierfache des C64-Pixeltakts; die CPU macht alle 32 Takte einen
//         Schritt (984 kHz, 0,09 % langsamer als ein echter PAL-C64).
//         HDMI_TX_CLK ist derselbe Takt um 180 Grad verschoben: Die Daten
//         wechseln mit clk_sys, der Sender übernimmt sie eine halbe Periode
//         später, mitten im gültigen Bereich.
//         Asynchrone Eingänge kommen nur über sync_2ff herein.
// Ports:  Namen wie im Terasic-Handbuch (Großschreibung nur hier im Top-Level).
//         KEY und LEDR sind low-aktiv; intern wird alles high-aktiv geführt.
// IP:     pll_c64 (50 MHz -> 2 x 31,5 MHz, 0 und 180 Grad) und reset_release
//         sind Intel-IP (quartus/ip/*.ip) und nicht simulierbar — deshalb
//         bleibt hier nur Verdrahtung.

`default_nettype none

module de25_nano_top #(
    // Original-ROMs des C64: liegen nur lokal in roms/ und werden von
    // sw/py/build_rom.py umgewandelt. Ohne sie: banktest_basic.hex,
    // banktest_char.hex und banktest_kernal.hex eintragen (Test-ROMs).
    parameter BASIC_FILE        = "../sw/asm/build/c64_basic.hex",
    parameter CHAR_FILE         = "../sw/asm/build/c64_chargen.hex",
    parameter KERNAL_FILE       = "../sw/asm/build/c64_kernal.hex"
) (
    input  wire        CLOCK0_50,
    input  wire [1:0]  KEY,
    input  wire [3:0]  SW,
    output wire [7:0]  LEDR,
    output wire        FPGA_UART_TX,
    input  wire        FPGA_UART_RX,
    output wire        HDMI_TX_CLK,
    output wire [23:0] HDMI_TX_D,
    output wire        HDMI_TX_DE,
    output wire        HDMI_TX_HS,
    output wire        HDMI_TX_VS,
    output wire        HDMI_I2C_SCL,
    inout  wire        HDMI_I2C_SDA,
    input  wire        HDMI_TX_INT
);

    // Takte pro Zeiteinheit bei 31,5 MHz
    localparam CLK_HZ       = 31_500_000;
    localparam UART_DIV     = 273;              // 31,5 MHz / 273 = 115385 Baud (0,16 % daneben)
    localparam KEY_CLKS     = CLK_HZ / 25;      // 40 ms Tastendruck bzw. Pause
    localparam TIMEOUT_CLKS = CLK_HZ / 2;       // 0,5 s
    localparam I2C_QUARTER  = 79;               // 31,5 MHz / (4 * 79) = 100 kHz
    localparam STARTUP_CLKS = CLK_HZ / 5;       // 0,2 s

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
    // Taster, Schalter, ninit_done und locked in die Taktdomäne holen.
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

    blink #(.HALF_PERIOD(CLK_HZ / 2)) u_blink (
        .clk   (clk_sys),
        .rst   (rst),
        .led_q (heartbeat_q)
    );

    // --- Tastatur-Ersatz und Lader über den UART ----------------------------
    // Vom PC (115200 Baud) kommen Tastendrücke und Ladeblöcke. prg_loader
    // trennt sie: Tastendrücke warten in einer Schlange für 4096 Zeichen und
    // werden nacheinander getippt, Ladedaten gehen direkt ins RAM.
    wire [7:0]  rx_data_q;
    wire        rx_valid_q;
    wire        key_fifo_empty;
    wire        key_fifo_full;
    wire [7:0]  key_fifo_data;
    wire        key_fifo_rd;
    wire [63:0] keys;
    wire        typer_busy;
    wire [7:0]  key_data;
    wire        key_valid;
    wire        dma_req;
    wire [15:0] dma_addr;
    wire [7:0]  dma_data;
    wire        dma_ack;
    wire        loader_active;

    uart_rx #(.CLKS_PER_BIT(UART_DIV)) u_uart_rx (
        .clk     (clk_sys),
        .rst     (rst),
        .rxd     (FPGA_UART_RX),
        .data_q  (rx_data_q),
        .valid_q (rx_valid_q)
    );

    prg_loader #(.TIMEOUT_CLKS(TIMEOUT_CLKS)) u_prg_loader (
        .clk       (clk_sys),
        .rst       (rst),
        .rx_data   (rx_data_q),
        .rx_valid  (rx_valid_q),
        .key_data  (key_data),
        .key_valid (key_valid),
        .dma_req   (dma_req),
        .dma_addr  (dma_addr),
        .dma_data  (dma_data),
        .dma_ack   (dma_ack),
        .active    (loader_active)
    );

    fifo_sync #(.ADDR_W(12)) u_key_fifo (
        .clk    (clk_sys),
        .rst    (rst),
        .wr_en  (key_valid),
        .din    (key_data),
        .full   (key_fifo_full),
        .rd_en  (key_fifo_rd),
        .dout_q (key_fifo_data),
        .empty  (key_fifo_empty)
    );

    ascii_key_typer #(.PRESS_CLKS(KEY_CLKS), .RELEASE_CLKS(KEY_CLKS)) u_key_typer (
        .clk        (clk_sys),
        .rst        (rst),
        .fifo_empty (key_fifo_empty),
        .fifo_data  (key_fifo_data),
        .fifo_rd    (key_fifo_rd),
        .busy       (typer_busy),
        .keys       (keys)
    );

    // --- Der C64 ------------------------------------------------------------
    // ROM-Pfade relativ zum Quartus-Projektverzeichnis (quartus/).
    wire       pix_en;
    wire [3:0] vic_color;
    wire       vic_hblank;
    wire       vic_vblank;

    soc_c64 #(
        .BASIC_FILE        (BASIC_FILE),
        .CHAR_FILE         (CHAR_FILE),
        .KERNAL_FILE       (KERNAL_FILE),
        .PIX_DIV           (4),         // 31,5 MHz / 4 = Pixeltakt 7,875 MHz
        .UART_CLKS_PER_BIT (UART_DIV)
    ) u_soc_c64 (
        .clk        (clk_sys),
        .rst        (rst),
        .uart_txd   (FPGA_UART_TX),
        .keys       (keys),
        .dma_req    (dma_req),
        .dma_addr   (dma_addr),
        .dma_data   (dma_data),
        .dma_ack    (dma_ack),
        .pix_en     (pix_en),
        .vic_color  (vic_color),
        .vic_hblank (vic_hblank),
        .vic_vblank (vic_vblank)
    );

    // --- HDMI: C64-Bild oder Testbild ---------------------------------------
    wire [23:0] c64_rgb_q;
    wire        c64_de_q;
    wire        c64_hsync_q;
    wire        c64_vsync_q;

    video_scandoubler u_scandoubler (
        .clk     (clk_sys),
        .rst     (rst),
        .pix_en  (pix_en),
        .color   (vic_color),
        .hblank  (vic_hblank),
        .vblank  (vic_vblank),
        .r_q     (c64_rgb_q[23:16]),
        .g_q     (c64_rgb_q[15:8]),
        .b_q     (c64_rgb_q[7:0]),
        .de_q    (c64_de_q),
        .hsync_q (c64_hsync_q),
        .vsync_q (c64_vsync_q)
    );

    // Testbild im selben Raster (1008 x 624, sichtbar 720 x 576), das der
    // Monitortest bestätigt hat (siehe docs/pinout.md, Bildformat).
    wire [11:0] bars_x;
    wire [11:0] bars_y;
    wire        bars_de;
    wire        bars_hsync;
    wire        bars_vsync;

    video_timing #(
        .H_ACTIVE (720), .H_FP (72), .H_SYNC (96), .H_BP (120),
        .V_ACTIVE (576), .V_FP (8),  .V_SYNC (6),  .V_BP (34)
    ) u_bars_timing (
        .clk   (clk_sys),
        .rst   (rst),
        .en    (1'b1),
        .x_q   (bars_x),
        .y_q   (bars_y),
        .de    (bars_de),
        .hsync (bars_hsync),
        .vsync (bars_vsync)
    );

    wire [23:0] bars_rgb_q;
    wire        bars_de_q;
    wire        bars_hsync_q;
    wire        bars_vsync_q;

    video_colorbars #(.H_ACTIVE(720), .V_ACTIVE(576)) u_video_colorbars (
        .clk     (clk_sys),
        .en      (1'b1),
        .x       (bars_x),
        .y       (bars_y),
        .de      (bars_de),
        .hsync   (bars_hsync),
        .vsync   (bars_vsync),
        .r_q     (bars_rgb_q[23:16]),
        .g_q     (bars_rgb_q[15:8]),
        .b_q     (bars_rgb_q[7:0]),
        .de_q    (bars_de_q),
        .hsync_q (bars_hsync_q),
        .vsync_q (bars_vsync_q)
    );

    // Bildquelle wählen und noch einmal registern, damit Farbe und
    // Steuersignale gemeinsam und ohne Logik dahinter an die Pins gehen.
    reg [23:0] hdmi_rgb_q;
    reg        hdmi_de_q;
    reg        hdmi_hsync_q;
    reg        hdmi_vsync_q;

    always @(posedge clk_sys) begin
        hdmi_rgb_q   <= sw0_q ? bars_rgb_q   : c64_rgb_q;
        hdmi_de_q    <= sw0_q ? bars_de_q    : c64_de_q;
        hdmi_hsync_q <= sw0_q ? bars_hsync_q : c64_hsync_q;
        hdmi_vsync_q <= sw0_q ? bars_vsync_q : c64_vsync_q;
    end

    // Belegung wie in Terasics Demo: D[23:16] Rot, D[15:8] Grün, D[7:0] Blau.
    // 576p verlangt low-aktive Sync-Impulse.
    assign HDMI_TX_CLK = clk_sys_180;
    assign HDMI_TX_D   = hdmi_rgb_q;
    assign HDMI_TX_DE  = hdmi_de_q;
    assign HDMI_TX_HS  = ~hdmi_hsync_q;
    assign HDMI_TX_VS  = ~hdmi_vsync_q;

    // Konfiguration des HDMI-Senders über I2C. SDA wird nur auf 0 gezogen
    // oder losgelassen; SCL treibt das FPGA wie in Terasics Demo fest.
    wire hdmi_scl_oe_q;
    wire hdmi_sda_oe_q;
    wire hdmi_ready_q;
    wire hdmi_nack_q;

    hdmi_config #(.CLKS_PER_QUARTER(I2C_QUARTER), .STARTUP_CLKS(STARTUP_CLKS)) u_hdmi_config (
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

    // --- LEDs ---------------------------------------------------------------
    // Interne Sicht: 1 = LED an. Nur der Herzschlag ist angeschlossen.
    // Zum Fehlersuchen bieten sich an: hdmi_ready_q, hdmi_nack_q,
    // key_fifo_full, typer_busy, loader_active, rst.
    wire [7:0] led = {7'b0, heartbeat_q};

    assign LEDR = ~led;

endmodule

`default_nettype wire
