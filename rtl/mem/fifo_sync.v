// fifo_sync — Warteschlange (FIFO) mit einem Takt, als Block-RAM.
//
// Zweck:  Puffer zwischen einem schnellen Lieferanten und einem langsamen
//         Abnehmer, wie die Schlange an einer Kasse: Was zuerst hineingeht,
//         kommt zuerst heraus. Zwei Zeiger laufen im Kreis durch den
//         Speicher — einer zeigt auf den nächsten freien Platz, der andere
//         auf den ältesten Eintrag.
// Takt:   clk, synchroner Reset rst (aktiv high).
// Ports:  wr_en = 1 legt din ab, falls full = 0; sonst geht der Wert
//         verloren.
//         rd_en = 1 holt den ältesten Eintrag, falls empty = 0. Er liegt
//         einen Takt später an dout_q an.
// Größe:  2^ADDR_W Einträge.

`default_nettype none

module fifo_sync #(
    parameter ADDR_W = 12,
    parameter DATA_W = 8
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              wr_en,
    input  wire [DATA_W-1:0] din,
    output wire              full,
    input  wire              rd_en,
    output reg  [DATA_W-1:0] dout_q,
    output wire              empty
);

    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    // Ein Bit mehr als die Adresse: So lassen sich "leer" (Zeiger gleich)
    // und "voll" (eine ganze Runde Abstand) unterscheiden.
    reg [ADDR_W:0] wr_ptr_q;
    reg [ADDR_W:0] rd_ptr_q;

    assign empty = (wr_ptr_q == rd_ptr_q);
    assign full  = (wr_ptr_q == {~rd_ptr_q[ADDR_W], rd_ptr_q[ADDR_W-1:0]});

    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    always @(posedge clk) begin
        if (do_write) mem[wr_ptr_q[ADDR_W-1:0]] <= din;
        if (do_read)  dout_q <= mem[rd_ptr_q[ADDR_W-1:0]];
    end

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr_q <= {(ADDR_W+1){1'b0}};
            rd_ptr_q <= {(ADDR_W+1){1'b0}};
        end else begin
            if (do_write) wr_ptr_q <= wr_ptr_q + 1'b1;
            if (do_read)  rd_ptr_q <= rd_ptr_q + 1'b1;
        end
    end

endmodule

`default_nettype wire
