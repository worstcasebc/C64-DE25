// prg_loader — trennt den Datenstrom vom PC in Tastendrücke und Ladedaten.
//
// Zweck:  Über denselben UART kommen Tastendrücke und Programme. Ein
//         Ladeblock beginnt mit dem Byte $FF, das als Tastencode nie
//         vorkommt:
//           $FF, Adresse low, Adresse high, Länge low, Länge high, Daten...
//         Die Datenbytes werden der Reihe nach ab der Adresse direkt ins
//         RAM des C64 geschrieben (DMA, siehe soc_c64) — wie ein Lieferant
//         mit eigenem Schlüssel zum Lager, der nicht an der Kasse (CPU)
//         vorbei muss. Alles außerhalb eines Ladeblocks geht unverändert
//         als Tastendruck weiter.
// Takt:   clk, synchroner Reset rst (aktiv high).
// Ports:  rx_data/rx_valid — Bytes vom uart_rx (valid = 1 für einen Takt).
//         key_data/key_valid — Tastendrücke für die Warteschlange.
//         dma_req = 1: dma_data soll nach dma_addr geschrieben werden; die
//         Signale bleiben stehen, bis dma_ack = 1 das Schreiben bestätigt.
//         Das nächste Byte darf erst nach der Bestätigung eintreffen — beim
//         UART liegen dazwischen Tausende Takte.
//         active = 1 innerhalb eines Ladeblocks.
// Schutz: Bleibt ein Ladeblock unvollständig (Sender abgebrochen), endet er
//         nach TIMEOUT_CLKS Takten ohne neues Byte (Default 0,5 s), damit
//         nicht spätere Tastendrücke als Daten im RAM landen.

`default_nettype none

module prg_loader #(
    parameter TIMEOUT_CLKS = 25_000_000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output wire [7:0]  key_data,
    output wire        key_valid,
    output reg         dma_req,
    output reg  [15:0] dma_addr,
    output reg  [7:0]  dma_data,
    input  wire        dma_ack,
    output wire        active
);

    localparam [7:0] START = 8'hFF;

    localparam [2:0] S_IDLE    = 3'd0,
                     S_ADDR_LO = 3'd1,
                     S_ADDR_HI = 3'd2,
                     S_LEN_LO  = 3'd3,
                     S_LEN_HI  = 3'd4,
                     S_DATA    = 3'd5;

    localparam CNT_W = (TIMEOUT_CLKS > 1) ? $clog2(TIMEOUT_CLKS) : 1;

    reg [2:0]       state_q;
    reg [15:0]      next_addr_q;    // Adresse für das nächste Datenbyte
    reg [15:0]      remaining_q;    // noch erwartete Datenbytes
    reg [CNT_W-1:0] timeout_q;

    assign active    = (state_q != S_IDLE);
    assign key_data  = rx_data;
    assign key_valid = rx_valid && (state_q == S_IDLE) && (rx_data != START);

    always @(posedge clk) begin
        if (rst) begin
            state_q   <= S_IDLE;
            dma_req   <= 1'b0;
            timeout_q <= {CNT_W{1'b0}};
        end else begin
            if (dma_ack) dma_req <= 1'b0;

            // Zeitüberwachung: läuft nur innerhalb eines Ladeblocks.
            if (rx_valid || state_q == S_IDLE) begin
                timeout_q <= {CNT_W{1'b0}};
            end else if (timeout_q == TIMEOUT_CLKS - 1) begin
                state_q <= S_IDLE;
            end else begin
                timeout_q <= timeout_q + 1'b1;
            end

            if (rx_valid) begin
                case (state_q)
                    S_IDLE:    if (rx_data == START) state_q <= S_ADDR_LO;
                    S_ADDR_LO: begin next_addr_q[7:0]  <= rx_data; state_q <= S_ADDR_HI; end
                    S_ADDR_HI: begin next_addr_q[15:8] <= rx_data; state_q <= S_LEN_LO;  end
                    S_LEN_LO:  begin remaining_q[7:0]  <= rx_data; state_q <= S_LEN_HI;  end
                    S_LEN_HI: begin
                        remaining_q[15:8] <= rx_data;
                        state_q <= ({rx_data, remaining_q[7:0]} == 16'd0) ? S_IDLE : S_DATA;
                    end
                    S_DATA: begin
                        dma_req     <= 1'b1;
                        dma_addr    <= next_addr_q;
                        dma_data    <= rx_data;
                        next_addr_q <= next_addr_q + 1'b1;
                        remaining_q <= remaining_q - 1'b1;
                        if (remaining_q == 16'd1) state_q <= S_IDLE;
                    end
                    default:   state_q <= S_IDLE;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
