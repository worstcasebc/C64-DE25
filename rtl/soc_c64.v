// soc_c64 — der C64-Rechner: CPU, Speicher mit Banking, VIC-II, SID, zwei CIAs.
//
// Zweck:  CPU 6510 (der Core T65 unter rtl/cpu/vendor/t65: taktgenau und
//         mit den undokumentierten Befehlen; dazu der I/O-Port cpu_port)
//         + 64 KB RAM + BASIC-/Char-/KERNAL-ROM + Farb-RAM,
//         der VIC-II aus FPGA64 (rtl/video/vendor/fpga64), der SID aus
//         MiSTer (rtl/audio/vendor/mister_sid), CIA 1 mit Tastatur und
//         CIA 2 für die Speicherbank des VIC-II. Der UART bei $DE00 dient
//         als Debug-Ausgabe.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high).
//         Ein CPU-Takt des C64 besteht aus 8 Pixeln, jedes Pixel aus
//         PIX_DIV Systemtakten (auf dem Board 4: 31,5 MHz / 32 = 984 kHz;
//         in der Simulation geht auch 1, das spart Rechenzeit).
// Bus:    CPU und VIC-II teilen sich den Speicher wie zwei Köche eine
//         Küche im Schichtbetrieb:
//           Pixel 0-3 (phi = 0)  der VIC-II liest (Zeichen, Muster, Farbe)
//           Pixel 4-7 (phi = 1)  die CPU ist dran
//         Die CPU legt Adresse und Schreibdaten zu Beginn des CPU-Takts an
//         und hält sie. Am Anfang von Pixel 4 findet ihr Zugriff auf RAM,
//         ROMs, CIAs usw. statt (cpu_en_q); am Ende von Pixel 7 übernimmt
//         sie die gelesenen Daten und geht zum nächsten Takt über
//         (cpu_step).
//         Braucht der VIC-II mehr als seine halbe Schicht (in jeder achten
//         Bildzeile holt er 40 Zeichencodes, außerdem Sprite-Daten), nimmt
//         er die Leitung BA auf 0. Lesezugriffe der CPU finden dann nicht
//         statt, und sie wartet (Eingang rdy); Schreibzugriffe bringt sie
//         wie der echte 6510 noch zu Ende. In dieser Zeit liest der VIC-II
//         auch in der zweiten Hälfte.
//         Speicherkarte siehe c64_addr_decode, Banking siehe cpu_port.
//           $D000-$D3FF  VIC-II (Register alle 64 Adressen wiederholt)
//           $D400-$D7FF  SID (Register alle 32 Adressen wiederholt)
//           $D800-$DBFF  Farb-RAM, 4 Bit; obere Bits lesen als 1
//           $DC00-$DCFF  CIA 1 (aus MiSTer, taktgenau): Tastatur, Timer; ihr Interrupt geht an den
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
//         sid_audio — Tonsignal des SID mit Vorzeichen; ein neuer Wert pro
//         CPU-Takt, gültig bei cpu_tick = 1.
// SID:    Er braucht mindestens 16 Systemtakte pro CPU-Takt, um Ton zu
//         berechnen, also PIX_DIV >= 2. Mit PIX_DIV = 1 funktionieren nur
//         seine Registerzugriffe.

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
    output wire        vic_vblank,
    output wire [17:0] sid_audio,
    output wire        cpu_tick
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

    reg cpu_en_q;       // in diesem Takt greift die CPU auf den Bus zu
    reg dma_wr_q;       // dieser Takt gehört dem Lader
    reg tick_q;         // ein CPU-Takt ist vergangen (auch wenn die CPU steht)
    reg ba_q;           // BA zu Beginn der CPU-Hälfte, gilt für diesen CPU-Takt
    reg dma_cycle_q;    // dieser CPU-Takt gehört dem Lader: die CPU pausiert

    // Am Ende des CPU-Takts übernimmt die CPU die Lesedaten und macht den
    // nächsten Schritt. Ob sie bei BA = 0 wartet, entscheidet sie selbst
    // (Eingang rdy).
    wire cpu_step = sub_last && (pix_q == 3'd7) && !dma_cycle_q;

    assign dma_ack  = dma_wr_q;
    assign cpu_tick = tick_q;

    always @(posedge clk) begin
        if (rst) begin
            cpu_en_q    <= 1'b0;
            dma_wr_q    <= 1'b0;
            tick_q      <= 1'b0;
            ba_q        <= 1'b1;
            dma_cycle_q <= 1'b0;
        end else begin
            // Der Zugriff der CPU findet statt, wenn der VIC-II den Bus
            // nicht braucht (BA = 1) oder wenn es ein Schreibzugriff ist.
            cpu_en_q <= cpu_slot && !dma_req && (vic_ba || we);
            dma_wr_q <= cpu_slot && dma_req;
            tick_q   <= cpu_slot;
            if (cpu_slot) begin
                ba_q        <= vic_ba;
                dma_cycle_q <= dma_req;
            end
        end
    end

    // --- CPU ----------------------------------------------------------------
    wire cia1_irq;
    wire cia2_irq;
    wire vic_irq_n;

    cpu_t65 u_cpu (
        .clk  (clk),
        .rst  (rst),
        .en   (cpu_step),
        .rdy  (ba_q),
        .irq  (cia1_irq | ~vic_irq_n),
        .nmi  (cia2_irq),
        .addr (addr),
        .din  (cpu_din),
        .dout (cpu_dout),
        .we   (we)
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
    wire sel_sid   = sel_io & (addr[11:10] == 2'b01);  // $D400-$D7FF
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

    // --- SID ----------------------------------------------------------------
    // Ein SID vom Typ 6581 mit eingeschaltetem Filter. Die Eingänge für
    // Paddles (pot_*), externen Ton (ext_in) und das Nachladen von
    // Filterkurven (ld_*) bleiben unbenutzt; die Anschlüsse mit _r gehören
    // zu einem zweiten SID, den es hier nicht gibt (DUAL = 0).
    wire [7:0]  sid_dout;
    wire [17:0] sid_audio_r_unused;

    sid_top #(
        .MULTI_FILTERS (0),
        .DUAL          (0)
    ) u_sid (
        .reset       (rst),
        .clk         (clk),
        .ce_1m       (tick_q),
        .cs          (cpu_en_q & sel_sid),
        .we          (we),
        .addr        (addr[4:0]),
        .data_in     (cpu_dout),
        .data_out    (sid_dout),
        .fc_offset_l (13'd0),
        .pot_x_l     (8'hFF),
        .pot_y_l     (8'hFF),
        .ext_in_l    (18'd0),
        .audio_l     (sid_audio),
        .fc_offset_r (13'd0),
        .pot_x_r     (8'hFF),
        .pot_y_r     (8'hFF),
        .ext_in_r    (18'd0),
        .audio_r     (sid_audio_r_unused),
        .filter_en   (1'b1),
        .mode        (1'b0),
        .cfg         (2'b00),
        .ld_clk      (1'b0),
        .ld_addr     (12'd0),
        .ld_data     (16'd0),
        .ld_wr       (1'b0)
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

    // --- Die beiden CIAs (aus MiSTer, rtl/io/vendor/mister_cia) -------------
    // Sie arbeiten in zwei Schritten pro CPU-Takt:
    //   phi2_n  Buszugriff der CPU, zu Beginn der CPU-Hälfte (wie cpu_en_q,
    //           aber in jedem Takt — ob die CPU zugreift, sagt cs_n)
    //   phi2_p  Timer zählen, direkt nachdem die CPU ihren Schritt gemacht hat
    // Die Timer laufen also auch, wenn der VIC-II die CPU anhält.
    wire cia_phi2_n = tick_q;
    reg  cia_phi2_p_q;

    always @(posedge clk) begin
        if (rst) cia_phi2_p_q <= 1'b0;
        else     cia_phi2_p_q <= sub_last && (pix_q == 3'd7);
    end

    // CIA 1: Tastatur und Timer; Interrupt an den IRQ.
    // An den Ports zählt der Pegel der Leitung: was die CIA selbst ausgibt,
    // verknüpft mit dem, was von außen kommt (hier das Tastaturgitter).
    wire [7:0] cia1_dout;
    wire [7:0] cia1_pa_out;
    wire [7:0] cia1_pb_out;
    wire [7:0] cia1_pb_keys;
    wire       cia1_irq_n;

    key_matrix u_key_matrix (
        .keys (keys),
        .pa   (cia1_pa_out),
        .pb   (cia1_pb_keys)
    );

    mos6526 u_cia1 (
        .mode    (1'b0),            // 6526 (die ältere Bauart)
        .clk     (clk),
        .phi2_p  (cia_phi2_p_q),
        .phi2_n  (cia_phi2_n),
        .res_n   (~rst),
        .cs_n    (~(cpu_en_q & sel_cia1)),
        .rw      (~we),
        .rs      (addr[3:0]),
        .db_in   (cpu_dout),
        .db_out  (cia1_dout),
        .pa_in   (cia1_pa_out),
        .pa_out  (cia1_pa_out),
        .pa_oe   (),
        .pb_in   (cia1_pb_out & cia1_pb_keys),
        .pb_out  (cia1_pb_out),
        .pb_oe   (),
        .flag_n  (1'b1),
        .pc_n    (),
        .tod     (tod_tick_q),
        .sp_in   (1'b1),
        .sp_out  (),
        .cnt_in  (1'b1),
        .cnt_out (),
        .irq_n   (cia1_irq_n)
    );

    assign cia1_irq = ~cia1_irq_n;

    // CIA 2: Speicherbank des VIC-II; Interrupt an den NMI.
    wire [7:0] cia2_dout;
    wire [7:0] cia2_pa_out;
    wire [7:0] cia2_pb_out;
    wire       cia2_irq_n;

    mos6526 u_cia2 (
        .mode    (1'b0),
        .clk     (clk),
        .phi2_p  (cia_phi2_p_q),
        .phi2_n  (cia_phi2_n),
        .res_n   (~rst),
        .cs_n    (~(cpu_en_q & sel_cia2)),
        .rw      (~we),
        .rs      (addr[3:0]),
        .db_in   (cpu_dout),
        .db_out  (cia2_dout),
        .pa_in   (cia2_pa_out),
        .pa_out  (cia2_pa_out),
        .pa_oe   (),
        .pb_in   (cia2_pb_out),
        .pb_out  (cia2_pb_out),
        .pb_oe   (),
        .flag_n  (1'b1),
        .pc_n    (),
        .tod     (tod_tick_q),
        .sp_in   (1'b1),
        .sp_out  (),
        .cnt_in  (1'b1),
        .cnt_out (),
        .irq_n   (cia2_irq_n)
    );

    assign cia2_irq = ~cia2_irq_n;
    assign vic_bank = ~cia2_pa_out[1:0];

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
    // Die Speicher und Bausteine antworten einen Takt nach dem Zugriff; die
    // CPU übernimmt die Daten am Ende ihres Takts. Dazwischen wird gemerkt,
    // wer angesprochen war. Wichtig beim Banking: Es zählt die Auswahl zum
    // Zeitpunkt des Zugriffs.
    reg sel_port_q;
    reg sel_ram_q;
    reg sel_basic_q;
    reg sel_char_q;
    reg sel_kernal_q;
    reg sel_uart_q;
    reg sel_vic_q;
    reg sel_sid_q;
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
            sel_sid_q    <= sel_sid;
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
        else if (sel_vic_q)    cpu_din = vic_do;
        else if (sel_sid_q)    cpu_din = sid_dout;
        else if (sel_color_q)  cpu_din = {4'hF, color_dout};
        else if (sel_cia1_q)   cpu_din = cia1_dout;
        else if (sel_cia2_q)   cpu_din = cia2_dout;
        else                   cpu_din = 8'hFF;   // I/O-Fenster ohne Baustein
    end

endmodule

`default_nettype wire
