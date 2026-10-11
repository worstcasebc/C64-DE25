// soc_c64 — der C64-Rechner: CPU, Speicher mit Banking, VIC-II, zwei CIAs.
//
// Zweck:  6502 + CPU-Port + 64 KB RAM + BASIC-/Char-/KERNAL-ROM + Farb-RAM,
//         der VIC-II aus FPGA64 (rtl/video/vendor/fpga64), CIA 1 mit
//         Tastatur und CIA 2 für die Speicherbank des VIC-II. Der SID fehlt
//         noch; der UART bei $DE00 dient als Debug-Ausgabe.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high).
//         Ein CPU-Takt des C64 besteht aus 8 Pixeln, jedes Pixel aus
//         PIX_DIV Systemtakten (auf dem Board 4: 31,5 MHz / 32 = 984 kHz;
//         in der Simulation geht auch 1, das spart Rechenzeit).
// Bus:    CPU und VIC-II teilen sich den Speicher wie zwei Köche eine
//         Küche im Schichtbetrieb:
//           Pixel 0-3 (phi = 0)  der VIC-II liest (Zeichen, Muster, Farbe)
//           Pixel 4-7 (phi = 1)  die CPU ist dran — ein Schritt am Anfang
//                                von Pixel 4
//         Braucht der VIC-II mehr als seine halbe Schicht (in jeder achten
//         Bildzeile holt er 40 Zeichencodes, außerdem Sprite-Daten), nimmt
//         er die Leitung BA auf 0. Die CPU setzt dann ihre Schritte aus —
//         außer Schreibzugriffe, die sie wie der echte 6510 noch zu Ende
//         bringt. In dieser Zeit liest der VIC-II auch in der zweiten
//         Hälfte.
//         Die CPU spricht RAM, ROMs, CIAs usw. in ihrem Schritt an; die
//         Antwort liest sie im nächsten Schritt. Für den VIC-II werden
//         Adresse und Daten des Schritts festgehalten, weil er sie die
//         ganze CPU-Hälfte lang sehen will.
//         Speicherkarte siehe c64_addr_decode, Banking siehe cpu_port.
//           $D000-$D3FF  VIC-II (Register alle 64 Adressen wiederholt)
//           $D800-$DBFF  Farb-RAM, 4 Bit; obere Bits lesen als 1
//           $DC00-$DCFF  CIA 1: Tastatur, Timer; ihr Interrupt geht an den
//                        IRQ der CPU
//           $DD00-$DDFF  CIA 2: Port A Bit 0/1 (invertiert) wählen, welches
//                        16-KB-Viertel des Speichers der VIC-II sieht; ihr
//                        Interrupt geht an den NMI der CPU
//           $DE00-$DEFF  UART: schreiben = senden, lesen Bit 7 = frei
//         Der VIC-II sieht immer das RAM, nur bei $1000-$1FFF in den
//         Vierteln 0 und 2 stattdessen das Char-ROM.
// DMA:    Ein Lader (prg_loader) kann Bytes direkt ins RAM schreiben; er
//         bekommt dafür einmal den Schritt der CPU.
// Ports:  uart_txd — serielle Ausgabe, UART_CLKS_PER_BIT Takte pro Bit.
//         keys — gedrückte Tasten, siehe key_matrix.
//         dma_* — dma_req = 1 mit Adresse und Daten halten, bis dma_ack = 1.
//         pix_en = 1 für einen Takt pro Pixel; dazu vic_color (Farbnummer
//         0..15) und vic_hblank/vic_vblank (1 in der Zeilen- bzw.
//         Bildlücke). Das ist ein PAL-Raster: 504 Pixel, 312 Zeilen.

`default_nettype none

module soc_c64 #(
    parameter BASIC_FILE        = "sw/asm/build/banktest_basic.hex",
    parameter CHAR_FILE         = "sw/asm/build/banktest_char.hex",
    parameter KERNAL_FILE       = "sw/asm/build/banktest_kernal.hex",
    parameter PIX_DIV           = 4,
    parameter TOD_CPU_TICKS     = 19688,    // CPU-Takte pro 1/50 s für die Uhren der CIAs
    parameter UART_CLKS_PER_BIT = 273
) (
    input  wire        clk,
    input  wire        rst,
    output wire        uart_txd,
    input  wire [63:0] keys,
    input  wire        dma_req,
    input  wire [15:0] dma_addr,
    input  wire [7:0]  dma_data,
    output wire        dma_ack,
    output wire        pix_en,
    output wire [3:0]  vic_color,
    output wire        vic_hblank,
    output wire        vic_vblank
);

    // --- Phasen innerhalb eines CPU-Takts -----------------------------------
    localparam SUB_W = (PIX_DIV > 1) ? $clog2(PIX_DIV) : 1;

    reg [SUB_W-1:0] sub_q;      // Systemtakt innerhalb des Pixels
    reg [2:0]       pix_q;      // Pixel innerhalb des CPU-Takts, 0..7

    wire sub_last = (sub_q == PIX_DIV - 1);

    always @(posedge clk) begin
        if (rst) begin
            sub_q <= {SUB_W{1'b0}};
            pix_q <= 3'd0;
        end else if (sub_last) begin
            sub_q <= {SUB_W{1'b0}};
            pix_q <= pix_q + 1'b1;
        end else begin
            sub_q <= sub_q + 1'b1;
        end
    end

    // Freigaben für den VIC-II, so wie MiSTer sie erzeugt:
    wire phi       = pix_q[2];                          // 0: VIC-II, 1: CPU
    wire ena_pixel = sub_last;                          // letzter Takt jedes Pixels
    wire ena_data  = sub_last && (pix_q[1:0] == 2'd3);  // Ende jeder Hälfte: Daten übernehmen
    wire vic_read  = sub_last && (pix_q[1:0] == 2'd2);  // davor: Speicher für den VIC-II lesen
    wire cpu_slot  = sub_last && (pix_q == 3'd3);       // danach beginnt die CPU-Hälfte

    assign pix_en = ena_pixel;

    // --- Wer bekommt den Schritt: CPU, Lader oder niemand -------------------
    wire [15:0] addr;
    wire [7:0]  cpu_dout;
    wire        we;
    reg  [7:0]  cpu_din;
    wire        vic_ba;

    reg cpu_en_q;       // dieser Takt ist ein Schritt der CPU
    reg dma_wr_q;       // dieser Takt gehört dem Lader
    reg tick_q;         // ein CPU-Takt ist vergangen (auch wenn die CPU steht)

    assign dma_ack = dma_wr_q;

    always @(posedge clk) begin
        if (rst) begin
            cpu_en_q <= 1'b0;
            dma_wr_q <= 1'b0;
            tick_q   <= 1'b0;
        end else begin
            // Die CPU darf, wenn der VIC-II den Bus nicht braucht (BA = 1)
            // oder wenn ihr anstehender Zugriff ein Schreibzugriff ist.
            cpu_en_q <= cpu_slot && !dma_req && (vic_ba || we);
            dma_wr_q <= cpu_slot && dma_req;
            tick_q   <= cpu_slot;
        end
    end

    // --- CPU ----------------------------------------------------------------
    wire cia1_irq;
    wire cia2_irq;
    wire vic_irq_n;

    cpu_6502 u_cpu (
        .clk  (clk),
        .rst  (rst),
        .en   (cpu_en_q),
        .addr (addr),
        .din  (cpu_din),
        .dout (cpu_dout),
        .we   (we),
        .irq  (cia1_irq | ~vic_irq_n),
        .nmi  (cia2_irq)
    );

    // --- Address-Decoder ----------------------------------------------------
    wire loram;
    wire hiram;
    wire charen;
    wire sel_port;
    wire sel_ram;
    wire sel_basic;
    wire sel_char;
    wire sel_io;
    wire sel_kernal;

    c64_addr_decode u_addr_decode (
        .addr       (addr),
        .loram      (loram),
        .hiram      (hiram),
        .charen     (charen),
        .sel_port   (sel_port),
        .sel_ram    (sel_ram),
        .sel_basic  (sel_basic),
        .sel_char   (sel_char),
        .sel_io     (sel_io),
        .sel_kernal (sel_kernal)
    );

    wire sel_vic   = sel_io & (addr[11:10] == 2'b00);  // $D000-$D3FF
    wire sel_color = sel_io & (addr[11:10] == 2'b10);  // $D800-$DBFF
    wire sel_cia1  = sel_io & (addr[11:8] == 4'hC);    // $DC00-$DCFF
    wire sel_cia2  = sel_io & (addr[11:8] == 4'hD);    // $DD00-$DDFF
    wire sel_uart  = sel_io & (addr[11:8] == 4'hE);    // $DE00-$DEFF

    // --- CPU-Port -----------------------------------------------------------
    wire [7:0] port_dout;

    cpu_port u_cpu_port (
        .clk    (clk),
        .rst    (rst),
        .en     (cpu_en_q),
        .sel    (sel_port),
        .we     (we),
        .a0     (addr[0]),
        .din    (cpu_dout),
        .dout_q (port_dout),
        .loram  (loram),
        .hiram  (hiram),
        .charen (charen)
    );

    // --- Speicher: Anschluss A für CPU und Lader, Anschluss B für den VIC-II -
    wire [13:0] vic_addr;       // Adresse innerhalb des 16-KB-Viertels
    wire [1:0]  vic_bank;       // gewähltes Viertel (aus CIA 2)
    wire [15:0] vic_full_addr = {vic_bank, vic_addr};

    wire [7:0] ram_dout;
    wire [7:0] basic_dout;
    wire [7:0] char_dout;
    wire [7:0] kernal_dout;
    wire [3:0] color_dout;
    wire [7:0] vic_ram_dout;
    wire [7:0] vic_char_dout;
    wire [3:0] vic_color_dout;

    ram_dp_sync #(.ADDR_W(16)) u_ram (
        .clk      (clk),
        .a_en     (cpu_en_q),
        .a_we     (dma_wr_q | (cpu_en_q & we & ~sel_port & ~sel_io)),
        .a_addr   (dma_wr_q ? dma_addr : addr),
        .a_din    (dma_wr_q ? dma_data : cpu_dout),
        .a_dout_q (ram_dout),
        .b_en     (vic_read),
        .b_addr   (vic_full_addr),
        .b_dout_q (vic_ram_dout)
    );

    rom_sync #(.ADDR_W(13), .INIT_FILE(BASIC_FILE)) u_rom_basic (
        .clk    (clk),
        .en     (cpu_en_q),
        .addr   (addr[12:0]),
        .dout_q (basic_dout)
    );

    rom_dp_sync #(.ADDR_W(12), .INIT_FILE(CHAR_FILE)) u_rom_char (
        .clk      (clk),
        .a_en     (cpu_en_q),
        .a_addr   (addr[11:0]),
        .a_dout_q (char_dout),
        .b_en     (vic_read),
        .b_addr   (vic_addr[11:0]),
        .b_dout_q (vic_char_dout)
    );

    rom_sync #(.ADDR_W(13), .INIT_FILE(KERNAL_FILE)) u_rom_kernal (
        .clk    (clk),
        .en     (cpu_en_q),
        .addr   (addr[12:0]),
        .dout_q (kernal_dout)
    );

    ram_dp_sync #(.ADDR_W(10), .DATA_W(4)) u_color_ram (
        .clk      (clk),
        .a_en     (cpu_en_q),
        .a_we     (cpu_en_q & we & sel_color),
        .a_addr   (addr[9:0]),
        .a_din    (cpu_dout[3:0]),
        .a_dout_q (color_dout),
        .b_en     (vic_read),
        .b_addr   (vic_addr[9:0]),
        .b_dout_q (vic_color_dout)
    );

    // Der VIC-II sieht das Char-ROM bei $1000-$1FFF in den Vierteln 0 und 2.
    reg vic_char_sel_q;

    always @(posedge clk) begin
        if (vic_read) vic_char_sel_q <= (vic_full_addr[14:12] == 3'b001);
    end

    wire [7:0] vic_di = vic_char_sel_q ? vic_char_dout : vic_ram_dout;

    // --- VIC-II -------------------------------------------------------------
    // Registerzugriff der CPU: Adresse und Daten des Schritts festhalten.
    reg       vic_cs_q;
    reg       vic_we_q;
    reg [5:0] vic_reg_addr_q;
    reg [7:0] vic_reg_din_q;

    always @(posedge clk) begin
        if (rst) begin
            vic_cs_q <= 1'b0;
            vic_we_q <= 1'b0;
        end else if (cpu_en_q) begin
            vic_cs_q       <= sel_vic;
            vic_we_q       <= we;
            vic_reg_addr_q <= addr[5:0];
            vic_reg_din_q  <= cpu_dout;
        end else if (cpu_slot) begin
            vic_cs_q <= 1'b0;       // neuer CPU-Takt: alter Zugriff ist vorbei
        end
    end

    wire [7:0] vic_do;
    reg  [7:0] vic_dout_q;

    always @(posedge clk) begin
        if (ena_data && phi) vic_dout_q <= vic_do;     // Ende der CPU-Hälfte
    end

    video_vicii_656x #(
        .registeredAddress (1),
        .emulateRefresh    (1),
        .emulateLightpen   (0),
        .emulateGraphics   (1)
    ) u_vic (
        .clk         (clk),
        .phi         (phi),
        .enaData     (ena_data),
        .enaPixel    (ena_pixel),
        .baSync      (1'b0),
        .ba          (vic_ba),
        .ba_dma      (),
        .mode6569    (1'b1),        // PAL: 63 Takte pro Zeile, 312 Zeilen
        .mode6567old (1'b0),
        .mode6567R8  (1'b0),
        .mode6572    (1'b0),
        .turbo_en    (1'b0),
        .turbo_state (),
        .variant     (2'b00),
        .reset       (rst),
        .cs          (vic_cs_q),
        .we          (vic_we_q),
        .lp_n        (1'b1),
        .aRegisters  (vic_reg_addr_q),
        .diRegisters (vic_reg_din_q),
        .di          (vic_di),
        .diColor     (vic_color_dout),
        .do          (vic_do),
        .vicAddr     (vic_addr),
        .irq_n       (vic_irq_n),
        .hSync       (vic_hblank),
        .vSync       (vic_vblank),
        .colorIndex  (vic_color),
        .debugX      (),
        .debugY      (),
        .vicRefresh  (),
        .addrValid   ()
    );

    // --- 50-Hz-Takt für die Uhren der CIAs ----------------------------------
    // Im Original kommt er aus dem Stromnetz; hier wird er aus dem CPU-Takt
    // abgezählt.
    localparam TOD_W = $clog2(TOD_CPU_TICKS);

    reg [TOD_W-1:0] tod_cnt_q;
    reg             tod_tick_q;

    always @(posedge clk) begin
        if (rst) begin
            tod_cnt_q  <= {TOD_W{1'b0}};
            tod_tick_q <= 1'b0;
        end else begin
            tod_tick_q <= 1'b0;
            if (tick_q) begin
                if (tod_cnt_q == TOD_CPU_TICKS - 1) begin
                    tod_cnt_q  <= {TOD_W{1'b0}};
                    tod_tick_q <= 1'b1;
                end else begin
                    tod_cnt_q <= tod_cnt_q + 1'b1;
                end
            end
        end
    end

    // --- CIA 1: Tastatur und Timer-Interrupt --------------------------------
    wire [7:0] cia1_dout;
    wire [7:0] cia1_pa_out;
    wire [7:0] cia1_pb_out;
    wire [7:0] cia1_pb_in;

    key_matrix u_key_matrix (
        .keys (keys),
        .pa   (cia1_pa_out),
        .pb   (cia1_pb_in)
    );

    cia u_cia1 (
        .clk      (clk),
        .rst      (rst),
        .tick     (tick_q),
        .tod_tick (tod_tick_q),
        .en     (cpu_en_q),
        .sel    (sel_cia1),
        .we     (we),
        .addr   (addr[3:0]),
        .din    (cpu_dout),
        .dout_q (cia1_dout),
        .irq    (cia1_irq),
        .pa_out (cia1_pa_out),
        .pb_out (cia1_pb_out),
        .pa_in  (8'hFF),
        .pb_in  (cia1_pb_in),
        .flag_n (1'b1)
    );

    // --- CIA 2: Speicherbank des VIC-II, Interrupt an den NMI ---------------
    wire [7:0] cia2_dout;
    wire [7:0] cia2_pa_out;
    wire [7:0] cia2_pb_out;

    cia u_cia2 (
        .clk      (clk),
        .rst      (rst),
        .tick     (tick_q),
        .tod_tick (tod_tick_q),
        .en     (cpu_en_q),
        .sel    (sel_cia2),
        .we     (we),
        .addr   (addr[3:0]),
        .din    (cpu_dout),
        .dout_q (cia2_dout),
        .irq    (cia2_irq),
        .pa_out (cia2_pa_out),
        .pb_out (cia2_pb_out),
        .pa_in  (8'hFF),
        .pb_in  (8'hFF),
        .flag_n (1'b1)
    );

    assign vic_bank = ~cia2_pa_out[1:0];

    // Nicht benutzte Ausgänge der CIAs.
    wire unused_cia = &{cia1_pb_out, cia2_pa_out[7:2], cia2_pb_out};

    // --- UART-Register ------------------------------------------------------
    wire uart_ready;

    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart_tx (
        .clk   (clk),
        .rst   (rst),
        .data  (cpu_dout),
        .valid (cpu_en_q & we & sel_uart),
        .ready (uart_ready),
        .txd_q (uart_txd)
    );

    // --- Lesedaten zur CPU --------------------------------------------------
    // Alle antworten einen Schritt später; deshalb wird gemerkt, wer im
    // letzten Schritt angesprochen war. Wichtig beim Banking: Es zählt die
    // Auswahl zum Zeitpunkt des Zugriffs, nicht die danach.
    reg sel_port_q;
    reg sel_ram_q;
    reg sel_basic_q;
    reg sel_char_q;
    reg sel_kernal_q;
    reg sel_uart_q;
    reg sel_vic_q;
    reg sel_color_q;
    reg sel_cia1_q;
    reg sel_cia2_q;
    reg uart_ready_q;

    always @(posedge clk) begin
        if (cpu_en_q) begin
            sel_port_q   <= sel_port;
            sel_ram_q    <= sel_ram;
            sel_basic_q  <= sel_basic;
            sel_char_q   <= sel_char;
            sel_kernal_q <= sel_kernal;
            sel_uart_q   <= sel_uart;
            sel_vic_q    <= sel_vic;
            sel_color_q  <= sel_color;
            sel_cia1_q   <= sel_cia1;
            sel_cia2_q   <= sel_cia2;
            uart_ready_q <= uart_ready;
        end
    end

    always @* begin
        if      (sel_port_q)   cpu_din = port_dout;
        else if (sel_ram_q)    cpu_din = ram_dout;
        else if (sel_basic_q)  cpu_din = basic_dout;
        else if (sel_char_q)   cpu_din = char_dout;
        else if (sel_kernal_q) cpu_din = kernal_dout;
        else if (sel_uart_q)   cpu_din = {uart_ready_q, 7'b0};
        else if (sel_vic_q)    cpu_din = vic_dout_q;
        else if (sel_color_q)  cpu_din = {4'hF, color_dout};
        else if (sel_cia1_q)   cpu_din = cia1_dout;
        else if (sel_cia2_q)   cpu_din = cia2_dout;
        else                   cpu_din = 8'hFF;   // I/O-Fenster ohne Baustein
    end

endmodule

`default_nettype wire
