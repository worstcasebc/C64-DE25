// de25_nano_top — Top-Level, Stand Meilenstein 7 (C64 neben dem HPS).
//
// Zweck:  Verdrahtet den C64-Rechner mit dem Board. Mit dem Makro ENABLE_HPS
//         (gesetzt im Projekt quartus_hps/) kommt das HPS dazu, auf dem Linux
//         läuft; ohne das Makro (Projekt quartus/) bleibt es beim C64 allein.
//           KEY[0]    Reset
//           SW[0]     1 zeigt statt des C64-Bildes das Testbild mit
//                     Farbbalken
//           LEDR[0]   Zustand. Mit HPS (hps_status_led): blinkt schnell,
//                     solange der Dienst unter Linux fehlt (Linux bootet
//                     noch); leuchtet, wenn er läuft; blinkt langsam, wenn
//                     er ein Problem meldet. Ohne HPS: 1-Hz-Herzschlag aus
//                     clk_sys — blinkt nur, wenn die PLL läuft.
//           LEDR[1]   Leuchte des Diskettenlaufwerks 1541
//           LEDR[2]   nur mit HPS: Die Diskette hat Änderungen, die noch
//                     nicht in der Datei stehen — nicht ausschalten
//           übrige LEDs aus. Zum Fehlersuchen stehen intern Signale bereit,
//                     siehe unten in "LEDs".
//           FPGA_UART_TX  Textausgabe des 6502-Programms, 115200 Baud 8N1,
//                     über den FTDI-Chip am Type-C-Anschluss
//           FPGA_UART_RX  Tastatur-Ersatz: Zeichen aus dem Terminal werden
//                     auf der C64-Tastatur getippt (ascii_key_typer);
//                     Ladeblöcke gehen direkt ins RAM (prg_loader)
//           HDMI      Bild des VIC-II, zeilenverdoppelt (video_scandoubler):
//                     720 x 576 bei 50 Hz über den HDMI-Sender ADV7513.
//                     Dazu der Ton des SID als I2S (49,2 kHz, 16 Bit, auf
//                     beiden Kanälen dasselbe).
// Takte:  clk_sys = 31,5 MHz aus der PLL, die einzige Domäne. Das ist das
//         Vierfache des C64-Pixeltakts; die CPU macht alle 32 Takte einen
//         Schritt (984 kHz, 0,09 % langsamer als ein echter PAL-C64).
//         HDMI_TX_CLK ist derselbe Takt um 180 Grad verschoben: Die Daten
//         wechseln mit clk_sys, der Sender übernimmt sie eine halbe Periode
//         später, mitten im gültigen Bereich.
//         Asynchrone Eingänge kommen nur über sync_2ff herein.
//         Mit HPS gibt es eine zweite Domäne: clk_100 (100 MHz aus der PLL
//         "pll" an CLOCK2_50) für die Brücken zwischen HPS und FPGA. Von
//         Zwischen ihr und clk_sys gibt es zwei Übergänge: hps_byte_port,
//         über den Linux dieselben Bytes schickt wie der PC über
//         FPGA_UART_RX (dazu die Tasten), und hps_disk_port, über den Linux
//         dem Laufwerk die Diskette liefert.
// Ports:  Namen wie im Terasic-Handbuch (Großschreibung nur hier im Top-Level).
//         KEY und LEDR sind low-aktiv; intern wird alles high-aktiv geführt.
// IP:     pll_c64 (50 MHz -> 2 x 31,5 MHz, 0 und 180 Grad) und reset_release
//         sind Intel-IP (quartus/ip/*.ip) und nicht simulierbar — deshalb
//         bleibt hier nur Verdrahtung.
//         Mit HPS: qsys_top ist das Platform-Designer-System aus Terasics
//         Beispiel GHRD (quartus_hps/, siehe README dort). Es enthält das
//         HPS, dessen Speicher LPDDR4A und die Register an der Brücke; das
//         Signal ninit_done kommt dann von dort statt von reset_release.

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
    input  wire        HDMI_TX_INT,
    output wire        HDMI_MCLK,
    output wire        HDMI_SCLK,
    output wire        HDMI_LRCLK,
    output wire        HDMI_I2S

`ifdef ENABLE_HPS
    ,
    input  wire        CLOCK2_50,

    // Speicher des HPS (läuft über Pins des FPGA)
    input  wire        LPDDR4A_REFCLK_p,
    output wire        LPDDR4A_CS_n,
    output wire [5:0]  LPDDR4A_CA,
    output wire        LPDDR4A_CK,
    output wire        LPDDR4A_CKE,
    output wire        LPDDR4A_CK_n,
    inout  wire [3:0]  LPDDR4A_DM,
    inout  wire [31:0] LPDDR4A_DQ,
    inout  wire [3:0]  LPDDR4A_DQS,
    inout  wire [3:0]  LPDDR4A_DQS_n,
    output wire        LPDDR4A_RESET_n,
    input  wire        LPDDR4A_RZQ,

    // Anschlüsse des HPS: Netzwerk, SD-Karte, UART, USB, I2C, Taster, LED
    input  wire        HPS_CLK_25,
    output wire        HPS_ENET_MDC,
    inout  wire        HPS_ENET_MDIO,
    input  wire        HPS_ENET_RX_CLK,
    input  wire        HPS_ENET_RX_CTL,
    input  wire [3:0]  HPS_ENET_RX_DATA,
    output wire        HPS_ENET_TX_CLK,
    output wire        HPS_ENET_TX_CTL,
    output wire [3:0]  HPS_ENET_TX_DATA,
    inout  wire        HPS_GSENSOR_I2C_EN,
    inout  wire        HPS_GSENSOR_INT,
    inout  wire        HPS_I2C_SCL,
    inout  wire        HPS_I2C_SDA,
    inout  wire        HPS_KEY,
    inout  wire        HPS_LED,
    output wire        HPS_SD_CLK,
    inout  wire        HPS_SD_CMD,
    inout  wire [3:0]  HPS_SD_DATA,
    input  wire        HPS_UART_RX,
    output wire        HPS_UART_TX,
    input  wire        HPS_USB_CLK,
    inout  wire [7:0]  HPS_USB_DATA,
    input  wire        HPS_USB_DIR,
    input  wire        HPS_USB_NXT,
    output wire        HPS_USB_STP
`endif
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

`ifndef ENABLE_HPS
    reset_release u_reset_release (
        .ninit_done (ninit_done)
    );
`endif

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

    // Reset des C64: Taster, Start des FPGA, PLL — und mit HPS der Wunsch von
    // Linux (Menü). hps_reset_q ist schon in clk_sys synchronisiert.
    wire hps_reset_q;
    wire rst = key0_q | ninit_done_q | ~pll_locked_q | hps_reset_q;

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
    // Mit HPS kommen dieselben Bytes auch von Linux (hps_byte_port, siehe
    // unten bei "HPS"). Beide Quellen münden in einen Strom: Der UART hat
    // Vorrang, weil er nicht warten kann; ein Byte von Linux wartet, bis der
    // UART gerade nichts liefert, das vorige Ladebyte im RAM steht und die
    // Schlange der Tastendrücke Platz hat.
    wire [7:0]  rx_data_q;
    wire        rx_valid_q;
    wire [7:0]  hps_data_q;
    wire        hps_valid_q;
    // Tasten kommen aus zwei Quellen, die beide dasselbe Gitter bedienen:
    // die getippten Zeichen (typer_keys) und, mit HPS, die Tastatur an
    // Linux (hps_keys_q). Gedrückt ist, was eine der beiden drückt.
    wire [63:0] typer_keys;
    wire [63:0] hps_keys_q;
    wire        hps_restore_q;      // Taste RESTORE, nur von Linux
    wire [4:0]  hps_joy1_q;         // Joysticks, nur von Linux
    wire [4:0]  hps_joy2_q;
    wire        key_fifo_empty;
    wire        key_fifo_full;
    wire [7:0]  key_fifo_data;
    wire        key_fifo_rd;
    wire [63:0] keys = typer_keys | hps_keys_q;
    wire        typer_busy;
    wire [7:0]  key_data;
    wire        key_valid;
    wire        dma_req;
    wire [15:0] dma_addr;
    wire [7:0]  dma_data;
    wire        dma_ack;
    wire        loader_active;

    wire        hps_ready = !rx_valid_q && !dma_req && !key_fifo_full;
    wire [7:0]  in_data   = rx_valid_q ? rx_data_q : hps_data_q;
    wire        in_valid  = rx_valid_q || (hps_valid_q && hps_ready);

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
        .rx_data   (in_data),
        .rx_valid  (in_valid),
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
        .keys       (typer_keys)
    );

    // --- Der C64 ------------------------------------------------------------
    // ROM-Pfade relativ zum Quartus-Projektverzeichnis (quartus/).
    wire       pix_en;
    wire [3:0] vic_color;
    wire       vic_hblank;
    wire       vic_vblank;
    wire [17:0] sid_audio;
    wire        cpu_tick;
    // Serieller Bus: je Leitung, was der C64 und was das Laufwerk darauf gibt
    // (0 = zieht). ATN gibt nur der C64.
    wire        iec_atn;
    wire        iec_clk_c64;
    wire        iec_data_c64;
    wire        iec_clk_drive;
    wire        iec_data_drive;

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
        .joy1       (hps_joy1_q),
        .joy2       (hps_joy2_q),
        .restore    (hps_restore_q),
        .iec_atn_o  (iec_atn),
        .iec_clk_o  (iec_clk_c64),
        .iec_data_o (iec_data_c64),
        .iec_clk_i  (iec_clk_drive),
        .iec_data_i (iec_data_drive),
        .dma_req    (dma_req),
        .dma_addr   (dma_addr),
        .dma_data   (dma_data),
        .dma_ack    (dma_ack),
        .pix_en     (pix_en),
        .vic_color  (vic_color),
        .vic_hblank (vic_hblank),
        .vic_vblank (vic_vblank),
        .sid_audio  (sid_audio),
        .cpu_tick   (cpu_tick)
    );

    // --- Diskettenlaufwerk 1541 ---------------------------------------------
    // Hängt wie beim echten C64 am seriellen Bus. Die Diskette liefert Linux
    // (hps_disk_port, siehe unten bei "HPS"): Das Laufwerk fordert Spuren an
    // (sd_rd, sd_lba), Linux schickt sie aus der Abbilddatei.
    // Das Laufwerk läuft nur, solange Linux es eingeschaltet hat
    // (disk_drive_on) — also solange dort ein Lieferant seine Anforderungen
    // bedient; sonst wartete es ewig auf seine erste Spur. Ob eine Diskette
    // eingelegt ist, spielt dafür keine Rolle: Beim Wechsel bleibt es an.
    // Ohne HPS gibt es keinen Lieferanten, also auch kein Laufwerk am Bus.
    wire        drive_led;
    wire        disk_drive_on;
    wire        disk_present;
    wire        disk_mounted;
    wire        disk_readonly;
    wire        disk_gcr_mode;
    wire [31:0] sd_lba;
    wire [5:0]  sd_blk_cnt;
    wire        sd_rd;
    wire        sd_wr;
    wire        sd_ack;
    wire [13:0] sd_buff_addr;
    wire [7:0]  sd_buff_dout;
    wire [7:0]  sd_buff_din;
    wire        sd_buff_wr;

    drive_1541 u_drive_1541 (
        .clk          (clk_sys),
        .rst          (rst | ~disk_drive_on),
        .iec_atn_i    (iec_atn),
        .iec_clk_i    (iec_clk_c64),
        .iec_data_i   (iec_data_c64),
        .iec_clk_o    (iec_clk_drive),
        .iec_data_o   (iec_data_drive),
        .led          (drive_led),
        .img_mounted  (disk_mounted),
        .img_readonly (disk_readonly),
        .img_size     ({31'd0, disk_present}),  // gebraucht wird nur: 0 oder nicht
        .gcr_mode     (disk_gcr_mode),
        .sd_lba       (sd_lba),
        .sd_blk_cnt   (sd_blk_cnt),
        .sd_rd        (sd_rd),
        .sd_wr        (sd_wr),
        .sd_ack       (sd_ack),
        .sd_buff_addr (sd_buff_addr),
        .sd_buff_dout (sd_buff_dout),
        .sd_buff_din  (sd_buff_din),
        .sd_buff_wr   (sd_buff_wr)
    );

    // --- Ton: SID -> Mittelwert -> I2S zum HDMI-Sender ----------------------
    // Der SID liefert 18 Bit mit Vorzeichen, einmal pro CPU-Takt. Über HDMI
    // gehen die oberen 16 Bit des geglätteten Signals, links und rechts
    // gleich.
    wire signed [17:0] audio_avg_q;

    audio_boxcar #(.W(18)) u_audio_boxcar (
        .clk      (clk_sys),
        .rst      (rst),
        .in       (sid_audio),
        .in_valid (cpu_tick),
        .out_q    (audio_avg_q)
    );

    i2s_tx u_i2s_tx (
        .clk     (clk_sys),
        .rst     (rst),
        .left    (audio_avg_q[17:2]),
        .right   (audio_avg_q[17:2]),
        .mclk_q  (HDMI_MCLK),
        .sclk_q  (HDMI_SCLK),
        .lrclk_q (HDMI_LRCLK),
        .sdata_q (HDMI_I2S)
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

    // Über dem Bild des C64 liegt mit HPS das Menüfenster von Linux
    // (video_osd, siehe unten bei "HPS"); ohne HPS geht das Bild direkt
    // weiter.
    wire [23:0] osd_rgb_q;
    wire        osd_de_q;
    wire        osd_hsync_q;
    wire        osd_vsync_q;

    // Bildquelle wählen und noch einmal registern, damit Farbe und
    // Steuersignale gemeinsam und ohne Logik dahinter an die Pins gehen.
    reg [23:0] hdmi_rgb_q;
    reg        hdmi_de_q;
    reg        hdmi_hsync_q;
    reg        hdmi_vsync_q;

    always @(posedge clk_sys) begin
        hdmi_rgb_q   <= sw0_q ? bars_rgb_q   : osd_rgb_q;
        hdmi_de_q    <= sw0_q ? bars_de_q    : osd_de_q;
        hdmi_hsync_q <= sw0_q ? bars_hsync_q : osd_hsync_q;
        hdmi_vsync_q <= sw0_q ? bars_vsync_q : osd_vsync_q;
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

    // --- HPS -----------------------------------------------------------------
    // Verdrahtung wie in Terasics golden_top.v. Die Register für Taster,
    // Schalter und LEDs (led_pio) gibt es im System noch, sie sind hier aber
    // nicht angeschlossen; die LEDs des Boards zeigen jetzt Zustände an.
    // c64_m0 und disk_m0 sind zwei Stücke Avalon-Bus, die aus dem System
    // herausgeführt sind (Bridges c64_bridge und disk_bridge, von Hand
    // ergänzt, siehe quartus_hps/README.md). An c64_m0 hängt hps_byte_port
    // (Bytes, Tasten), an disk_m0 hps_disk_port (Diskette für das Laufwerk)
    // und video_osd (Menüfenster im Bild).
    wire [2:0] hps_led;         // led_pio von Terasic, nicht mehr an den LEDs
    wire       status_led;
    wire       unsaved_led;

`ifdef ENABLE_HPS
    wire clk_100;

    pll u_pll_hps (
        .refclk   (CLOCK2_50),
        .locked   (),
        .rst      (ninit_done),
        .outclk_0 (clk_100)
    );

    wire rst_av;

    sync_2ff u_sync_rst_av (
        .clk      (clk_100),
        .d_async  (ninit_done),
        .d_sync_q (rst_av)
    );

    wire [3:0]  c64_m0_address;     // in Bytes; Bit 3..2 wählt das Register
    wire        c64_m0_write;
    wire [31:0] c64_m0_writedata;
    wire [3:0]  c64_m0_byteenable;
    wire        c64_m0_read;
    wire [31:0] c64_m0_readdata;
    wire        c64_m0_readdatavalid;
    wire        c64_m0_waitrequest;

    hps_byte_port u_hps_byte_port (
        .clk_av            (clk_100),
        .rst_av            (rst_av),
        .avs_address       (c64_m0_address[3:2]),
        .avs_write         (c64_m0_write),
        .avs_writedata     (c64_m0_writedata),
        .avs_byteenable    (c64_m0_byteenable),
        .avs_read          (c64_m0_read),
        .avs_readdata      (c64_m0_readdata),
        .avs_readdatavalid (c64_m0_readdatavalid),
        .avs_waitrequest   (c64_m0_waitrequest),
        .clk               (clk_sys),
        .rst               (rst),
        .data_q            (hps_data_q),
        .valid_q           (hps_valid_q),
        .ready             (hps_ready),
        .keys_q            (hps_keys_q),
        .restore_q         (hps_restore_q),
        .joy1_q            (hps_joy1_q),
        .joy2_q            (hps_joy2_q),
        .reset_q           (hps_reset_q)
    );

    wire [13:0] disk_m0_address;    // in Bytes; ab 0x2000 der Puffer
    wire        disk_m0_write;
    wire [31:0] disk_m0_writedata;
    wire [3:0]  disk_m0_byteenable;
    wire        disk_m0_read;
    wire [31:0] disk_m0_readdata;
    wire        disk_m0_readdatavalid;
    wire        disk_m0_waitrequest;

    hps_disk_port u_hps_disk_port (
        .clk_av            (clk_100),
        .rst_av            (rst_av),
        .avs_address       (disk_m0_address[13:2]),
        .avs_write         (disk_m0_write),
        .avs_writedata     (disk_m0_writedata),
        .avs_byteenable    (disk_m0_byteenable),
        .avs_read          (disk_m0_read),
        .avs_readdata      (disk_m0_readdata),
        .avs_readdatavalid (disk_m0_readdatavalid),
        .avs_waitrequest   (disk_m0_waitrequest),
        .clk               (clk_sys),
        .rst               (rst),
        .sd_lba            (sd_lba),
        .sd_blk_cnt        (sd_blk_cnt),
        .sd_rd             (sd_rd),
        .sd_wr             (sd_wr),
        .sd_ack            (sd_ack),
        .sd_buff_addr      (sd_buff_addr),
        .sd_buff_dout      (sd_buff_dout),
        .sd_buff_din       (sd_buff_din),
        .sd_buff_wr        (sd_buff_wr),
        .img_mounted       (disk_mounted),
        .img_present       (disk_present),
        .img_readonly      (disk_readonly),
        .gcr_mode          (disk_gcr_mode),
        .drive_on          (disk_drive_on)
    );

    // Zustands-LED: Der Dienst unter Linux meldet sich regelmäßig mit einem
    // Schreibzugriff auf Wort 3 des Bereichs von hps_disk_port (0x2001_400C),
    // das jenes Modul nicht benutzt. Alles bleibt im Takt der Brücke; die
    // Ausgänge gehen nur an LEDs.
    hps_status_led u_hps_status_led (
        .clk     (clk_100),
        .rst     (rst_av),
        .wr      (disk_m0_write && disk_m0_address[13:2] == 12'd3 && disk_m0_byteenable[0]),
        .wr_data (disk_m0_writedata[1:0]),
        .alive_q (),
        .led_q   (status_led),
        .aux_q   (unsaved_led)
    );

    // Das Menüfenster teilt sich den Bus mit hps_disk_port: Es hört nur auf
    // Schreibzugriffe im Bereich 0x1000 bis 0x1FFF, den hps_disk_port nicht
    // benutzt (und beim Lesen mit 0 beantwortet).
    video_osd #(.CHAR_FILE(CHAR_FILE)) u_video_osd (
        .clk_av         (clk_100),
        .rst_av         (rst_av),
        .avs_address    (disk_m0_address[11:2]),
        .avs_write      (disk_m0_write && disk_m0_address[13:12] == 2'b01),
        .avs_writedata  (disk_m0_writedata),
        .avs_byteenable (disk_m0_byteenable),
        .clk            (clk_sys),
        .rgb            (c64_rgb_q),
        .de             (c64_de_q),
        .hsync          (c64_hsync_q),
        .vsync          (c64_vsync_q),
        .rgb_q          (osd_rgb_q),
        .de_q           (osd_de_q),
        .hsync_q        (osd_hsync_q),
        .vsync_q        (osd_vsync_q)
    );

    qsys_top u_qsys_top (
        .disk_m0_waitrequest                   (disk_m0_waitrequest),
        .disk_m0_readdata                      (disk_m0_readdata),
        .disk_m0_readdatavalid                 (disk_m0_readdatavalid),
        .disk_m0_burstcount                    (),
        .disk_m0_writedata                     (disk_m0_writedata),
        .disk_m0_address                       (disk_m0_address),
        .disk_m0_write                         (disk_m0_write),
        .disk_m0_read                          (disk_m0_read),
        .disk_m0_byteenable                    (disk_m0_byteenable),
        .disk_m0_debugaccess                   (),
        .c64_m0_waitrequest                    (c64_m0_waitrequest),
        .c64_m0_readdata                       (c64_m0_readdata),
        .c64_m0_readdatavalid                  (c64_m0_readdatavalid),
        .c64_m0_burstcount                     (),
        .c64_m0_writedata                      (c64_m0_writedata),
        .c64_m0_address                        (c64_m0_address),
        .c64_m0_write                          (c64_m0_write),
        .c64_m0_read                           (c64_m0_read),
        .c64_m0_byteenable                     (c64_m0_byteenable),
        .c64_m0_debugaccess                    (),

        .clk_100_clk                           (clk_100),
        .reset_reset_n                         (~ninit_done),
        .ninit_done_ninit_done                 (ninit_done),
        .led_pio_external_connection_in_port   (hps_led),
        .led_pio_external_connection_out_port  (hps_led),
        .dipsw_pio_external_connection_export  (4'b0000),
        .button_pio_external_connection_export (4'b1111),

        .hps_io_hps_osc_clk                    (HPS_CLK_25),
        .emif_hps_emif_mem_0_mem_cs            (LPDDR4A_CS_n),
        .emif_hps_emif_mem_0_mem_ca            (LPDDR4A_CA),
        .emif_hps_emif_mem_0_mem_cke           (LPDDR4A_CKE),
        .emif_hps_emif_mem_0_mem_dq            (LPDDR4A_DQ),
        .emif_hps_emif_mem_0_mem_dqs_t         (LPDDR4A_DQS),
        .emif_hps_emif_mem_0_mem_dqs_c         (LPDDR4A_DQS_n),
        .emif_hps_emif_mem_0_mem_dmi           (LPDDR4A_DM),
        .emif_hps_emif_mem_ck_0_mem_ck_t       (LPDDR4A_CK),
        .emif_hps_emif_mem_ck_0_mem_ck_c       (LPDDR4A_CK_n),
        .emif_hps_emif_mem_reset_n_mem_reset_n (LPDDR4A_RESET_n),
        .emif_hps_emif_oct_0_oct_rzqin         (LPDDR4A_RZQ),
        .emif_hps_emif_ref_clk_0_clk           (LPDDR4A_REFCLK_p),
        .hps_io_emac0_tx_clk                   (HPS_ENET_TX_CLK),
        .hps_io_emac0_rx_clk                   (HPS_ENET_RX_CLK),
        .hps_io_emac0_tx_ctl                   (HPS_ENET_TX_CTL),
        .hps_io_emac0_rx_ctl                   (HPS_ENET_RX_CTL),
        .hps_io_emac0_txd0                     (HPS_ENET_TX_DATA[0]),
        .hps_io_emac0_txd1                     (HPS_ENET_TX_DATA[1]),
        .hps_io_emac0_txd2                     (HPS_ENET_TX_DATA[2]),
        .hps_io_emac0_txd3                     (HPS_ENET_TX_DATA[3]),
        .hps_io_emac0_rxd0                     (HPS_ENET_RX_DATA[0]),
        .hps_io_emac0_rxd1                     (HPS_ENET_RX_DATA[1]),
        .hps_io_emac0_rxd2                     (HPS_ENET_RX_DATA[2]),
        .hps_io_emac0_rxd3                     (HPS_ENET_RX_DATA[3]),
        .hps_io_mdio0_mdio                     (HPS_ENET_MDIO),
        .hps_io_mdio0_mdc                      (HPS_ENET_MDC),
        .hps_io_sdmmc_cclk                     (HPS_SD_CLK),
        .hps_io_sdmmc_cmd                      (HPS_SD_CMD),
        .hps_io_sdmmc_data0                    (HPS_SD_DATA[0]),
        .hps_io_sdmmc_data1                    (HPS_SD_DATA[1]),
        .hps_io_sdmmc_data2                    (HPS_SD_DATA[2]),
        .hps_io_sdmmc_data3                    (HPS_SD_DATA[3]),
        .hps_io_uart1_rx                       (HPS_UART_RX),
        .hps_io_uart1_tx                       (HPS_UART_TX),
        .hps_io_usb0_clk                       (HPS_USB_CLK),
        .hps_io_usb0_stp                       (HPS_USB_STP),
        .hps_io_usb0_dir                       (HPS_USB_DIR),
        .hps_io_usb0_nxt                       (HPS_USB_NXT),
        .hps_io_usb0_data0                     (HPS_USB_DATA[0]),
        .hps_io_usb0_data1                     (HPS_USB_DATA[1]),
        .hps_io_usb0_data2                     (HPS_USB_DATA[2]),
        .hps_io_usb0_data3                     (HPS_USB_DATA[3]),
        .hps_io_usb0_data4                     (HPS_USB_DATA[4]),
        .hps_io_usb0_data5                     (HPS_USB_DATA[5]),
        .hps_io_usb0_data6                     (HPS_USB_DATA[6]),
        .hps_io_usb0_data7                     (HPS_USB_DATA[7]),
        .hps_io_i2c1_sda                       (HPS_I2C_SDA),
        .hps_io_i2c1_scl                       (HPS_I2C_SCL),
        .hps_io_gpio28                         (HPS_GSENSOR_INT),
        .hps_io_gpio34                         (HPS_GSENSOR_I2C_EN),
        .hps_io_gpio40                         (HPS_KEY),
        .hps_io_gpio41                         (HPS_LED)
    );
`else
    assign hps_led     = 3'b000;
    assign status_led  = heartbeat_q;    // ohne HPS: Herzschlag
    assign unsaved_led = 1'b0;
    assign hps_data_q  = 8'h00;
    assign hps_valid_q = 1'b0;
    assign hps_keys_q  = 64'd0;
    assign hps_restore_q = 1'b0;
    assign hps_joy1_q    = 5'd0;
    assign hps_joy2_q    = 5'd0;
    assign hps_reset_q   = 1'b0;
    assign osd_rgb_q     = c64_rgb_q;
    assign osd_de_q      = c64_de_q;
    assign osd_hsync_q   = c64_hsync_q;
    assign osd_vsync_q   = c64_vsync_q;
    assign disk_drive_on = 1'b0;
    assign disk_present  = 1'b0;
    assign disk_mounted  = 1'b0;
    assign disk_readonly = 1'b0;
    assign disk_gcr_mode = 1'b0;
    assign sd_ack        = 1'b0;
    assign sd_buff_addr  = 14'd0;
    assign sd_buff_dout  = 8'd0;
    assign sd_buff_wr    = 1'b0;
`endif

    // --- LEDs ---------------------------------------------------------------
    // Interne Sicht: 1 = LED an. LED 0 zeigt den Zustand (siehe Kopf), LED 1
    // ist die Leuchte des Laufwerks, LED 2 warnt vor ungespeicherten
    // Änderungen an der Diskette. status_led und unsaved_led gehören mit HPS
    // zur Domäne clk_100 und gehen ohne Synchronizer hinaus: Sie sind nur
    // fürs Auge.
    // Zum Fehlersuchen bieten sich an: hdmi_ready_q, hdmi_nack_q,
    // key_fifo_full, typer_busy, loader_active, rst.
    wire [7:0] led = {5'b0, unsaved_led, drive_led, status_led};

    assign LEDR = ~led;

endmodule

`default_nettype wire
