// soc_c64 — Rechner mit C64-Speicherkarte (Meilenstein 3).
//
// Zweck:  6502 + CPU-Port + 64 KB RAM + BASIC-/Char-/KERNAL-ROM mit Banking
//         wie im C64. Video, SID und CIAs fehlen noch; im I/O-Fenster sitzt
//         vorerst nur der UART als Debug-Ausgabe.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high). Die CPU und
//         alles am Bus arbeiten nur in Takten mit cpu_en_q = 1, also jeden
//         CPU_DIV-ten Takt (Default 50 MHz / 50 = 1 MHz).
// Bus:    Speicherkarte siehe c64_addr_decode, Banking siehe cpu_port.
//         Das RAM liegt unter allem: Schreiben geht immer ins RAM, außer bei
//         CPU-Port und sichtbarem I/O.
//         $DE00-$DEFF schreiben: Byte senden. Lesen: Bit 7 = 1, wenn der
//         Sender frei ist. Restliches I/O-Fenster: liest $FF.
// Ports:  uart_txd — serielle Ausgabe, UART_CLKS_PER_BIT Takte pro Bit.

`default_nettype none

module soc_c64 #(
    parameter BASIC_FILE        = "sw/asm/build/banktest_basic.hex",
    parameter CHAR_FILE         = "sw/asm/build/banktest_char.hex",
    parameter KERNAL_FILE       = "sw/asm/build/banktest_kernal.hex",
    parameter CPU_DIV           = 50,
    parameter UART_CLKS_PER_BIT = 434
) (
    input  wire clk,
    input  wire rst,
    output wire uart_txd
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

    wire sel_uart = sel_io & (addr[11:8] == 4'hE);     // $DE00-$DEFF

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

    ram_sync #(.ADDR_W(16)) u_ram (
        .clk    (clk),
        .en     (cpu_en_q),
        .we     (we & ~sel_port & ~sel_io),
        .addr   (addr),
        .din    (cpu_dout),
        .dout_q (ram_dout)
    );

    rom_sync #(.ADDR_W(13), .INIT_FILE(BASIC_FILE)) u_rom_basic (
        .clk    (clk),
        .en     (cpu_en_q),
        .addr   (addr[12:0]),
        .dout_q (basic_dout)
    );

    rom_sync #(.ADDR_W(12), .INIT_FILE(CHAR_FILE)) u_rom_char (
        .clk    (clk),
        .en     (cpu_en_q),
        .addr   (addr[11:0]),
        .dout_q (char_dout)
    );

    rom_sync #(.ADDR_W(13), .INIT_FILE(KERNAL_FILE)) u_rom_kernal (
        .clk    (clk),
        .en     (cpu_en_q),
        .addr   (addr[12:0]),
        .dout_q (kernal_dout)
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
    reg uart_ready_q;

    always @(posedge clk) begin
        if (cpu_en_q) begin
            sel_port_q   <= sel_port;
            sel_ram_q    <= sel_ram;
            sel_basic_q  <= sel_basic;
            sel_char_q   <= sel_char;
            sel_kernal_q <= sel_kernal;
            sel_uart_q   <= sel_uart;
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
        else                   cpu_din = 8'hFF;   // I/O-Fenster ohne Baustein
    end

endmodule

`default_nettype wire
