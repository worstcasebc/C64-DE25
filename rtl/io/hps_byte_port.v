// hps_byte_port — Briefkasten für Bytes von Linux (HPS) an den C64.
//
// Zweck:  Linux schreibt ein Byte in ein Register an der Brücke; das Byte
//         taucht auf der Seite des C64 als Datenstrom auf, so wie die Bytes
//         vom uart_rx. Beide Seiten haben eigene Takte, die nichts
//         voneinander wissen. Deshalb läuft die Übergabe wie an einem
//         Briefkasten mit Fähnchen:
//           1. Linux legt den Brief ein (data_av_q) und stellt das Fähnchen
//              um (req_tgl_q wechselt).
//           2. Die C64-Seite sieht das Fähnchen erst zwei Takte später
//              (sync_2ff). Der Brief liegt dann längst ruhig da und darf
//              ohne eigenen Synchronizer gelesen werden.
//           3. Hat der Abnehmer das Byte übernommen, stellt die C64-Seite
//              ihr eigenes Fähnchen um (ack_tgl_q). Sieht Linux beide
//              Fähnchen gleich stehen, ist der Briefkasten wieder frei.
//         Über die Taktgrenze gehen also nur zwei einzelne Bits (je ein
//         sync_2ff) und die acht Datenbits, die währenddessen stillstehen.
// Takte:  Zwei Domänen — die einzige Stelle, an der sie sich berühren.
//           clk_av  Takt der Brücke (100 MHz), Reset rst_av
//           clk     Takt des C64 (31,5 MHz), Reset rst
//         Beide Resets synchron und aktiv high. rst_av darf nur zusammen mit
//         rst kommen (Einschalten). rst allein (Reset-Taster des C64) wirft
//         ein wartendes Byte weg und gibt den Briefkasten frei.
// Ports:  Seite HPS, Avalon-MM-Slave (avs_*):
//           avs_address 0  DATA    Schreiben: Bit 7..0 = Byte für den C64.
//                                  Wird ignoriert, solange belegt.
//                                  Lesen: das zuletzt angenommene Byte.
//           avs_address 1  STATUS  Lesen: Bit 0 = 1, solange belegt.
//           avs_byteenable[0] muss beim Schreiben gesetzt sein; so löst ein
//           Zugriff, den Linux in einzelne Bytes zerlegt, nur einmal aus.
//           avs_readdatavalid kommt einen Takt nach avs_read;
//           avs_waitrequest ist immer 0. Lesen ändert nichts.
//         Seite C64, Datenstrom:
//           valid_q = 1: data_q ist ein neues Byte und bleibt stehen, bis
//           der Abnehmer ready = 1 zeigt. In diesem Takt gilt das Byte als
//           übergeben.

`default_nettype none

module hps_byte_port (
    input  wire        clk_av,
    input  wire        rst_av,
    input  wire        avs_address,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire [3:0]  avs_byteenable,
    input  wire        avs_read,
    output reg  [31:0] avs_readdata,
    output reg         avs_readdatavalid,
    output wire        avs_waitrequest,

    input  wire        clk,
    input  wire        rst,
    output reg  [7:0]  data_q,
    output reg         valid_q,
    input  wire        ready
);

    reg       req_tgl_q;    // Fähnchen der HPS-Seite (clk_av)
    reg       ack_tgl_q;    // Fähnchen der C64-Seite (clk)
    reg [7:0] data_av_q;    // der Brief; steht still, solange belegt

    // --- Seite HPS (clk_av) -------------------------------------------------
    wire ack_sync_q;

    sync_2ff u_sync_ack (
        .clk      (clk_av),
        .d_async  (ack_tgl_q),
        .d_sync_q (ack_sync_q)
    );

    wire busy    = (req_tgl_q != ack_sync_q);
    wire do_send = avs_write && !avs_address && avs_byteenable[0] && !busy;

    assign avs_waitrequest = 1'b0;

    always @(posedge clk_av) begin
        if (rst_av) begin
            req_tgl_q         <= 1'b0;
            avs_readdatavalid <= 1'b0;
        end else begin
            if (do_send) begin
                data_av_q <= avs_writedata[7:0];
                req_tgl_q <= ~req_tgl_q;
            end
            avs_readdatavalid <= avs_read;
            avs_readdata      <= avs_address ? {31'b0, busy} : {24'b0, data_av_q};
        end
    end

    // --- Seite C64 (clk) ----------------------------------------------------
    wire req_sync_q;

    sync_2ff u_sync_req (
        .clk      (clk),
        .d_async  (req_tgl_q),
        .d_sync_q (req_sync_q)
    );

    always @(posedge clk) begin
        if (rst) begin
            // Fähnchen nachziehen statt auf 0 setzen: Was gerade unterwegs
            // ist, gilt damit als erledigt.
            valid_q   <= 1'b0;
            ack_tgl_q <= req_sync_q;
        end else if (!valid_q) begin
            if (req_sync_q != ack_tgl_q) begin
                data_q  <= data_av_q;
                valid_q <= 1'b1;
            end
        end else if (ready) begin
            valid_q   <= 1'b0;
            ack_tgl_q <= ~ack_tgl_q;
        end
    end

endmodule

`default_nettype wire
