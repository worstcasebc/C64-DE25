// uart_hello — sendet bei jeder steigenden Flanke von start einen festen Text.
//
// Zweck:  Übergangsmodul zum Testen von UART-Verdrahtung und Terminal, bevor
//         die CPU die Textausgabe übernimmt. Entfällt danach wieder.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high).
// Ports:  start — bereits synchronisierter Pegel (z. B. Taster);
//         tx_data/tx_valid/tx_ready — Handshake zu uart_tx.

`default_nettype none

module uart_hello (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    output wire [7:0] tx_data,
    output wire       tx_valid,
    input  wire       tx_ready
);

    // \015 = CR, \n = LF (Verilog-2001 kennt kein \r).
    localparam               LEN = 20;
    localparam [8*LEN-1:0]   MSG = "DE25-Nano: UART ok\015\n";

    reg       start_q;    // Vorwert von start für die Flankenerkennung
    reg       active_q;
    reg [4:0] idx_q;

    assign tx_valid = active_q;
    assign tx_data  = MSG[8*(LEN-1-idx_q) +: 8];   // erstes Zeichen steht ganz links

    always @(posedge clk) begin
        if (rst) begin
            start_q  <= 1'b0;
            active_q <= 1'b0;
            idx_q    <= 5'd0;
        end else begin
            start_q <= start;
            if (!active_q) begin
                if (start && !start_q) begin
                    active_q <= 1'b1;
                    idx_q    <= 5'd0;
                end
            end else if (tx_ready) begin        // Byte wurde in diesem Takt übernommen
                if (idx_q == LEN - 1) active_q <= 1'b0;
                else                  idx_q    <= idx_q + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
