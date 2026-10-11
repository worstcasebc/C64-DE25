// uart_rx — UART-Empfänger, Format 8N1 (1 Startbit, 8 Datenbits LSB zuerst,
//           kein Paritätsbit, 1 Stoppbit).
//
// Zweck:  Liest ein Byte bitweise von der Leitung rxd. Nach der fallenden
//         Flanke des Startbits wird eine halbe Bitzeit gewartet und dann
//         jedes Bit in seiner Mitte abgetastet — dort ist der Pegel am
//         sichersten. Ein Bit dauert CLKS_PER_BIT Takte; Default
//         50 MHz / 115200 Baud = 434.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high). rxd ist
//         asynchron und läuft intern über sync_2ff.
// Ports:  rxd — serielle Leitung, Ruhepegel 1.
//         valid_q = 1 für einen Takt, wenn data_q ein neues Byte enthält.
//         Bytes mit fehlendem Stoppbit werden verworfen.

`default_nettype none

module uart_rx #(
    parameter CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rxd,
    output reg  [7:0] data_q,
    output reg        valid_q
);

    localparam             CNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    localparam [CNT_W-1:0] HALF  = CLKS_PER_BIT / 2;

    wire rxd_sync_q;

    sync_2ff u_sync_rxd (
        .clk      (clk),
        .d_async  (rxd),
        .d_sync_q (rxd_sync_q)
    );

    reg             busy_q;
    reg [7:0]       shift_q;
    reg [3:0]       bits_q;    // Nummer des erwarteten Bits (0 = Startbit, 9 = Stoppbit)
    reg [CNT_W-1:0] baud_q;    // Taktzähler bis zur nächsten Bitmitte

    always @(posedge clk) begin
        if (rst) begin
            busy_q  <= 1'b0;
            valid_q <= 1'b0;
        end else begin
            valid_q <= 1'b0;

            if (!busy_q) begin
                if (!rxd_sync_q) begin
                    busy_q <= 1'b1;
                    bits_q <= 4'd0;
                    baud_q <= HALF;     // erste Abtastung nach einer halben Bitzeit
                end
            end else if (baud_q == CLKS_PER_BIT - 1) begin
                baud_q <= {CNT_W{1'b0}};
                bits_q <= bits_q + 1'b1;
                if (bits_q == 4'd0) begin
                    if (rxd_sync_q) busy_q <= 1'b0;     // nur ein Störimpuls
                end else if (bits_q == 4'd9) begin
                    busy_q <= 1'b0;
                    if (rxd_sync_q) begin               // Stoppbit vorhanden
                        data_q  <= shift_q;
                        valid_q <= 1'b1;
                    end
                end else begin
                    shift_q <= {rxd_sync_q, shift_q[7:1]};
                end
            end else begin
                baud_q <= baud_q + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
