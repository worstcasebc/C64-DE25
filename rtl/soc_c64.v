// soc_c64 — Rechner mit C64-Speicherkarte (Meilenstein 3).
//
// Zweck:  6502 + CPU-Port + 64 KB RAM + BASIC-/Char-/KERNAL-ROM mit Banking
//         wie im C64. SID und CIAs fehlen noch; vom VIC-II gibt es nur die
//         Farbregister (vic_stub). Dazu das Farb-RAM und der UART als
//         Debug-Ausgabe.
//         Das Video (video_text) liest über einen zweiten Anschluss direkt
//         aus RAM, Farb-RAM und Char-ROM, unabhängig von CPU und Banking —
//         so wie der VIC-II im echten C64.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high). Die CPU und
//         alles am Bus arbeiten nur in Takten mit cpu_en_q = 1, also jeden
//         CPU_DIV-ten Takt (Default 50 MHz / 50 = 1 MHz).
// Bus:    Speicherkarte siehe c64_addr_decode, Banking siehe cpu_port.
//         Das RAM liegt unter allem: Schreiben geht immer ins RAM, außer bei
//         CPU-Port und sichtbarem I/O.
//         $DE00-$DEFF schreiben: Byte senden. Lesen: Bit 7 = 1, wenn der
//         Sender frei ist.
//         $D000-$D3FF: VIC-Register, siehe vic_stub.
//         $D800-$DBFF: Farb-RAM, 1000 Zellen zu 4 Bit — die Farbe jedes
//         Zeichens. Die oberen vier Bits lesen hier als 1 (im echten C64
//         sind sie zufällig).
//         Restliches I/O-Fenster: liest $FF.
// Ports:  uart_txd — serielle Ausgabe, UART_CLKS_PER_BIT Takte pro Bit.
//         vid_* — Lese-Anschluss für das Video: Adresse anlegen, Daten
//         erscheinen einen Takt mit vid_en = 1 später.
//         border_color/bg_color — Farbnummern aus $D020/$D021.

`default_nettype none

module soc_c64 #(
    parameter BASIC_FILE        = "sw/asm/build/banktest_basic.hex",
    parameter CHAR_FILE         = "sw/asm/build/banktest_char.hex",
    parameter KERNAL_FILE       = "sw/asm/build/banktest_kernal.hex",
    parameter CPU_DIV           = 50,
    parameter UART_CLKS_PER_BIT = 434
) (
    input  wire        clk,
    input  wire        rst,
    output wire        uart_txd,
    input  wire        vid_en,
    input  wire [15:0] vid_ram_addr,
    output wire [7:0]  vid_ram_dout,
    input  wire [9:0]  vid_color_addr,
    output wire [3:0]  vid_color_dout,
    input  wire [11:0] vid_char_addr,
    output wire [7:0]  vid_char_dout,
    output wire [3:0]  border_color,
    output wire [3:0]  bg_color
);

    // --- Taktfreigabe für die CPU -------------------------------------------
    localparam DIV_W = (CPU_DIV > 1) ? $clog2(CPU_DIV) : 1;

    reg [DIV_W-1:0] div_q;
    reg             cpu_en_q;

    always @(posedge clk) begin
        if (rst) begin
            div_q    <= {DIV_W{1'b0}};
            cpu_en_q <= 1'b0;
        end else if (div_q == CPU_DIV - 1) begin
            div_q    <= {DIV_W{1'b0}};
            cpu_en_q <= 1'b1;
        end else begin
            div_q    <= div_q + 1'b1;
            cpu_en_q <= 1'b0;
        end
    end

    // --- CPU ----------------------------------------------------------------
    wire [15:0] addr;
    wire [7:0]  cpu_dout;
    wire        we;
    reg  [7:0]  cpu_din;

    cpu_6502 u_cpu (
        .clk  (clk),
        .rst  (rst),
        .en   (cpu_en_q),
        .addr (addr),
        .din  (cpu_din),
        .dout (cpu_dout),
        .we   (we),
        .irq  (1'b0),
        .nmi  (1'b0)
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

    wire sel_uart  = sel_io & (addr[11:8] == 4'hE);    // $DE00-$DEFF
    wire sel_vic   = sel_io & (addr[11:10] == 2'b00);  // $D000-$D3FF
    wire sel_color = sel_io & (addr[11:10] == 2'b10);  // $D800-$DBFF

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

    // --- Speicher -----------------------------------------------------------
    wire [7:0] ram_dout;
    wire [7:0] basic_dout;
    wire [7:0] char_dout;
    wire [7:0] kernal_dout;

    ram_dp_sync #(.ADDR_W(16)) u_ram (
        .clk      (clk),
        .a_en     (cpu_en_q),
        .a_we     (we & ~sel_port & ~sel_io),
        .a_addr   (addr),
        .a_din    (cpu_dout),
        .a_dout_q (ram_dout),
        .b_en     (vid_en),
        .b_addr   (vid_ram_addr),
        .b_dout_q (vid_ram_dout)
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
        .b_en     (vid_en),
        .b_addr   (vid_char_addr),
        .b_dout_q (vid_char_dout)
    );

    rom_sync #(.ADDR_W(13), .INIT_FILE(KERNAL_FILE)) u_rom_kernal (
        .clk    (clk),
        .en     (cpu_en_q),
        .addr   (addr[12:0]),
        .dout_q (kernal_dout)
    );

    // --- VIC-Register und Farb-RAM ------------------------------------------
    wire [7:0] vic_dout;
    wire [3:0] color_dout;

    vic_stub u_vic_stub (
        .clk            (clk),
        .rst            (rst),
        .en             (cpu_en_q),
        .sel            (sel_vic),
        .we             (we),
        .addr           (addr[5:0]),
        .din            (cpu_dout),
        .dout_q         (vic_dout),
        .border_color_q (border_color),
        .bg_color_q     (bg_color)
    );

    ram_dp_sync #(.ADDR_W(10), .DATA_W(4)) u_color_ram (
        .clk      (clk),
        .a_en     (cpu_en_q),
        .a_we     (we & sel_color),
        .a_addr   (addr[9:0]),
        .a_din    (cpu_dout[3:0]),
        .a_dout_q (color_dout),
        .b_en     (vid_en),
        .b_addr   (vid_color_addr),
        .b_dout_q (vid_color_dout)
    );

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
    // Die Speicher antworten einen Schritt später; deshalb wird gemerkt, wer
    // im letzten Schritt angesprochen war. Wichtig beim Banking: Es zählt
    // die Auswahl zum Zeitpunkt des Zugriffs, nicht die danach.
    reg sel_port_q;
    reg sel_ram_q;
    reg sel_basic_q;
    reg sel_char_q;
    reg sel_kernal_q;
    reg sel_uart_q;
    reg sel_vic_q;
    reg sel_color_q;
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
        else if (sel_vic_q)    cpu_din = vic_dout;
        else if (sel_color_q)  cpu_din = {4'hF, color_dout};
        else                   cpu_din = 8'hFF;   // I/O-Fenster ohne Baustein
    end

endmodule

`default_nettype wire
