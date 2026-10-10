// uart_tx — UART-Sender, Format 8N1 (1 Startbit, 8 Datenbits LSB zuerst,
//           kein Paritätsbit, 1 Stoppbit).
//
// Zweck:  Schiebt ein Byte bitweise auf die Leitung txd. Jedes Bit liegt
//         CLKS_PER_BIT Takte an; Default 50 MHz / 115200 Baud = 434.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high).
// Ports:  data/valid/ready — Handshake: Ein Byte wird in dem Takt übernommen,
//         in dem valid und ready beide 1 sind. ready ist 0, solange gesendet
//         wird. txd_q — serielle Leitung, Ruhepegel 1.

`default_nettype none

module uart_tx #(
    parameter CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       valid,
    output wire       ready,
    output reg        txd_q
);

    localparam CNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;

    reg             busy_q;
    reg [8:0]       shift_q;   // {Stoppbit, 8 Datenbits}
    reg [3:0]       bits_q;    // Nummer des gerade gesendeten Bits (0 = Startbit)
    reg [CNT_W-1:0] baud_q;    // Taktzähler innerhalb eines Bits

    assign ready = ~busy_q;

    always @(posedge clk) begin
        if (rst) begin
            busy_q <= 1'b0;
            txd_q  <= 1'b1;
        end else if (!busy_q) begin
            if (valid) begin
                busy_q  <= 1'b1;
                txd_q   <= 1'b0;             // Startbit
                shift_q <= {1'b1, data};
                bits_q  <= 4'd0;
                baud_q  <= {CNT_W{1'b0}};
            end
        end else if (baud_q == CLKS_PER_BIT - 1) begin
            baud_q <= {CNT_W{1'b0}};
            if (bits_q == 4'd9) begin
                busy_q <= 1'b0;              // Stoppbit ist vollständig gesendet
            end else begin
                txd_q   <= shift_q[0];
                shift_q <= {1'b1, shift_q[8:1]};
                bits_q  <= bits_q + 1'b1;
            end
        end else begin
            baud_q <= baud_q + 1'b1;
        end
    end

endmodule

`default_nettype wire
