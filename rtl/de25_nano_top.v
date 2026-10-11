// de25_nano_top — Top-Level, Stand Meilenstein 4 (Textmodus über HDMI).
//
// Zweck:  Board-Test für Takt, Reset, PLL, Taster, Schalter und LEDs.
//           LEDR[0]   1-Hz-Herzschlag aus clk_50  (Boardtakt)
//           LEDR[2:1] Schalter SW[1:0]; SW[0] = 1 zeigt statt des
//                     C64-Bildes das Testbild mit Farbbalken
//           LEDR[3]   HDMI-Sender bestätigt den letzten I2C-Zugriff nicht,
//                     oder die Warteschlange der Tastatur ist voll
//           LEDR[4]   HDMI-Sender fertig konfiguriert
//           LEDR[5]   KEY1 gedrückt oder es wird gerade getippt
//           LEDR[6]   2-Hz-Herzschlag aus clk_100 (PLL) — blinkt nur, wenn
//                     die PLL eingerastet ist
//           LEDR[7]   Reset aktiv (KEY0 gedrückt)
//           FPGA_UART_TX  Textausgabe des 6502-Programms, 115200 Baud 8N1,
//                     über den FTDI-Chip am Type-C-Anschluss
//           FPGA_UART_RX  Tastatur-Ersatz: Zeichen aus dem Terminal werden
//                     auf der C64-Tastatur getippt (ascii_key_typer)
//           HDMI      C64-Textbildschirm (video_text) in 640x480 über den
//                     HDMI-Sender ADV7513
// Takte:  clk_50  = CLOCK0_50 (50 MHz, Boardoszillator)
//         clk_100 = PLL-Ausgang (100 MHz, aus clk_50 abgeleitet)
//         Übergänge zwischen den Domänen nur über sync_2ff.
//         Das Video läuft in clk_50 mit Taktfreigabe in jedem zweiten Takt
//         (Pixeltakt 25 MHz statt der genormten 25,175 MHz, also 59,5 Hz).
// Ports:  Namen wie im Terasic-Handbuch (Großschreibung nur hier im Top-Level).
//         KEY und LEDR sind low-aktiv; intern wird alles high-aktiv geführt.
// IP:     pll_sys und reset_release sind Intel-IP (quartus/ip/*.ip) und in
//         Icarus nicht simulierbar — deshalb bleibt hier nur Verdrahtung.

`default_nettype none

module de25_nano_top #(
    parameter BLINK_HALF_PERIOD = 25_000_000,  // Takte pro halber Blinkperiode
    // Original-ROMs des C64: liegen nur lokal in roms/ und werden von
    // sw/py/build_rom.py umgewandelt. Ohne sie: banktest_basic.hex,
    // banktest_char.hex und banktest_kernal.hex eintragen (Test-ROMs).
    parameter BASIC_FILE        = "../sw/asm/build/c64_basic.hex",
    parameter CHAR_FILE         = "../sw/asm/build/c64_chargen.hex",
    parameter KERNAL_FILE       = "../sw/asm/build/c64_kernal.hex"
) (
    input  wire       CLOCK0_50,
    input  wire [1:0] KEY,
    input  wire [3:0] SW,
    output wire [7:0] LEDR,
    output wire       FPGA_UART_TX,
    input  wire       FPGA_UART_RX,
    output wire        HDMI_TX_CLK,
    output wire [23:0] HDMI_TX_D,
    output wire        HDMI_TX_DE,
    output wire        HDMI_TX_HS,
    output wire        HDMI_TX_VS,
    output wire        HDMI_I2C_SCL,
    inout  wire        HDMI_I2C_SDA,
    input  wire        HDMI_TX_INT
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

    // Pixeltakt: pix_clk_q wechselt in jedem Takt und geht als 25-MHz-Takt
    // an den HDMI-Sender. Die Videoregister schalten in den Takten mit
    // pix_clk_q = 1, also genau dann, wenn der Takt am Pin fällt. Der Sender
    // übernimmt die Daten mit der steigenden Flanke — 20 ns später, mitten im
    // gültigen Bereich.
    reg pix_clk_q;

    always @(posedge clk_50) begin
        if (rst) pix_clk_q <= 1'b0;
        else     pix_clk_q <= ~pix_clk_q;
    end

    wire pix_en = pix_clk_q;

    // Tastatur-Ersatz: Zeichen vom PC (115200 Baud) warten in einer
    // Schlange für 4096 Zeichen und werden nacheinander getippt.
    wire [7:0]  rx_data_q;
    wire        rx_valid_q;
    wire        key_fifo_empty;
    wire        key_fifo_full;
    wire [7:0]  key_fifo_data;
    wire        key_fifo_rd;
    wire [63:0] keys;
    wire        typer_busy;

    uart_rx #(.CLKS_PER_BIT(434)) u_uart_rx (
        .clk     (clk_50),
        .rst     (rst),
        .rxd     (FPGA_UART_RX),
        .data_q  (rx_data_q),
        .valid_q (rx_valid_q)
    );

    fifo_sync #(.ADDR_W(12)) u_key_fifo (
        .clk    (clk_50),
        .rst    (rst),
        .wr_en  (rx_valid_q),
        .din    (rx_data_q),
        .full   (key_fifo_full),
        .rd_en  (key_fifo_rd),
        .dout_q (key_fifo_data),
        .empty  (key_fifo_empty)
    );

    ascii_key_typer u_key_typer (
        .clk        (clk_50),
        .rst        (rst),
        .fifo_empty (key_fifo_empty),
        .fifo_data  (key_fifo_data),
        .fifo_rd    (key_fifo_rd),
        .busy       (typer_busy),
        .keys       (keys)
    );

    // Rechner mit C64-Speicherkarte. Das Video liest über vid_* aus RAM und
    // Char-ROM. ROM-Pfade relativ zum Quartus-Projektverzeichnis (quartus/).
    wire [15:0] vid_ram_addr;
    wire [7:0]  vid_ram_dout;
    wire [9:0]  vid_color_addr;
    wire [3:0]  vid_color_dout;
    wire [11:0] vid_char_addr;
    wire [7:0]  vid_char_dout;
    wire [3:0]  border_color;
    wire [3:0]  bg_color;

    soc_c64 #(
        .BASIC_FILE        (BASIC_FILE),
        .CHAR_FILE         (CHAR_FILE),
        .KERNAL_FILE       (KERNAL_FILE),
        .CPU_DIV           (50),    // 50 MHz / 50  = 1 MHz CPU-Schritte
        .UART_CLKS_PER_BIT (434)    // 50 MHz / 434 = 115200 Baud
    ) u_soc_c64 (
        .clk            (clk_50),
        .rst            (rst),
        .uart_txd       (FPGA_UART_TX),
        .keys           (keys),
        .vid_en         (pix_en),
        .vid_ram_addr   (vid_ram_addr),
        .vid_ram_dout   (vid_ram_dout),
        .vid_color_addr (vid_color_addr),
        .vid_color_dout (vid_color_dout),
        .vid_char_addr  (vid_char_addr),
        .vid_char_dout  (vid_char_dout),
        .border_color   (border_color),
        .bg_color       (bg_color)
    );

    // --- HDMI: C64-Textbildschirm oder Testbild ------------------------------
    wire [11:0] video_x;
    wire [11:0] video_y;
    wire        video_de;
    wire        video_hsync;
    wire        video_vsync;

    video_timing u_video_timing (
        .clk   (clk_50),
        .rst   (rst),
        .en    (pix_en),
        .x_q   (video_x),
        .y_q   (video_y),
        .de    (video_de),
        .hsync (video_hsync),
        .vsync (video_vsync)
    );

    wire [23:0] text_rgb_q;
    wire        text_de_q;
    wire        text_hsync_q;
    wire        text_vsync_q;

    video_text u_video_text (
        .clk          (clk_50),
        .en           (pix_en),
        .x            (video_x),
        .y            (video_y),
        .de           (video_de),
        .hsync        (video_hsync),
        .vsync        (video_vsync),
        .border_color (border_color),
        .bg_color     (bg_color),
        .ram_addr     (vid_ram_addr),
        .ram_dout     (vid_ram_dout),
        .color_addr   (vid_color_addr),
        .color_dout   (vid_color_dout),
        .char_addr    (vid_char_addr),
        .char_dout    (vid_char_dout),
        .r_q          (text_rgb_q[23:16]),
        .g_q          (text_rgb_q[15:8]),
        .b_q          (text_rgb_q[7:0]),
        .de_q         (text_de_q),
        .hsync_q      (text_hsync_q),
        .vsync_q      (text_vsync_q)
    );

    wire [23:0] bars_rgb_q;
    wire        bars_de_q;
    wire        bars_hsync_q;
    wire        bars_vsync_q;

    video_colorbars u_video_colorbars (
        .clk     (clk_50),
        .en      (pix_en),
        .x       (video_x),
        .y       (video_y),
        .de      (video_de),
        .hsync   (video_hsync),
        .vsync   (video_vsync),
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

    always @(posedge clk_50) begin
        if (pix_en) begin
            hdmi_rgb_q   <= sw_q[0] ? bars_rgb_q   : text_rgb_q;
            hdmi_de_q    <= sw_q[0] ? bars_de_q    : text_de_q;
            hdmi_hsync_q <= sw_q[0] ? bars_hsync_q : text_hsync_q;
            hdmi_vsync_q <= sw_q[0] ? bars_vsync_q : text_vsync_q;
        end
    end

    // Belegung wie in Terasics Demo: D[23:16] Rot, D[15:8] Grün, D[7:0] Blau.
    // 640x480 verlangt low-aktive Sync-Impulse.
    assign HDMI_TX_CLK = pix_clk_q;
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

    hdmi_config u_hdmi_config (
        .clk      (clk_50),
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
    wire [7:0] led = {rst, heartbeat_100_q, key_q[1] | typer_busy, hdmi_ready_q, hdmi_nack_q | key_fifo_full,
                      sw_q[1:0], heartbeat_50_q};

    assign LEDR = ~led;

endmodule

`default_nettype wire
