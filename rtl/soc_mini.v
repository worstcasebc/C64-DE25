// soc_mini — Mini-Rechner für Meilenstein 2: 6502 + RAM + ROM + UART.
//
// Zweck:  Erstes lauffähiges System: Ein Assembler-Programm im ROM gibt Text
//         über das UART-Register aus.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high). Die CPU und
//         alles am Bus arbeiten nur in Takten mit cpu_en_q = 1, also jeden
//         CPU_DIV-ten Takt (Default 50 MHz / 50 = 1 MHz).
// Bus:    Speicherkarte siehe addr_decode.
//         $DE00 schreiben: Byte senden. $DE00 lesen: Bit 7 = 1, wenn der
//         Sender frei ist (sonst würde das Byte verworfen).
// Ports:  uart_txd — serielle Ausgabe, UART_CLKS_PER_BIT Takte pro Bit.

`default_nettype none

module soc_mini #(
    parameter ROM_FILE          = "sw/asm/build/hello.hex",
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
    wire sel_ram;
    wire sel_uart;
    wire sel_rom;

    addr_decode u_addr_decode (
        .addr     (addr),
        .sel_ram  (sel_ram),
        .sel_uart (sel_uart),
        .sel_rom  (sel_rom)
    );

    // --- Speicher -----------------------------------------------------------
    wire [7:0] ram_dout;
    wire [7:0] rom_dout;

    ram_sync #(.ADDR_W(15)) u_ram (
        .clk    (clk),
        .en     (cpu_en_q),
        .we     (we & sel_ram),
        .addr   (addr[14:0]),
        .din    (cpu_dout),
        .dout_q (ram_dout)
    );

    rom_sync #(.ADDR_W(13), .INIT_FILE(ROM_FILE)) u_rom (
        .clk    (clk),
        .en     (cpu_en_q),
        .addr   (addr[12:0]),
        .dout_q (rom_dout)
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
    // im letzten Schritt angesprochen war.
    reg sel_ram_q;
    reg sel_rom_q;
    reg sel_uart_q;
    reg uart_ready_q;

    always @(posedge clk) begin
        if (cpu_en_q) begin
            sel_ram_q    <= sel_ram;
            sel_rom_q    <= sel_rom;
            sel_uart_q   <= sel_uart;
            uart_ready_q <= uart_ready;
        end
    end

    always @* begin
        if      (sel_ram_q)  cpu_din = ram_dout;
        else if (sel_rom_q)  cpu_din = rom_dout;
        else if (sel_uart_q) cpu_din = {uart_ready_q, 7'b0};
        else                 cpu_din = 8'hFF;   // unbelegter Bereich
    end

endmodule

`default_nettype wire
