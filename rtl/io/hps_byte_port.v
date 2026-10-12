// hps_byte_port — Register, über die Linux (HPS) den C64 bedient: ein
//                 Briefkasten für Bytes und der Zustand der Tastatur.
//
// Zweck:  Bytes: Linux schreibt ein Byte in ein Register an der Brücke; das
//         Byte taucht auf der Seite des C64 als Datenstrom auf, so wie die
//         Bytes vom uart_rx. Beide Seiten haben eigene Takte, die nichts
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
//         Über die Taktgrenze gehen dabei nur zwei einzelne Bits (je ein
//         sync_2ff) und die acht Datenbits, die währenddessen stillstehen.
//         Tasten: 64 Bit, eines pro Taste im Gitter des C64 (Nummern wie in
//         key_matrix, 1 = gedrückt). Linux schreibt hinein, welche Tasten
//         gerade unten sind; jedes Bit läuft einzeln durch einen sync_2ff.
//         Ein Handschlag ist hier nicht nötig: Jedes Bit gilt für sich, und
//         ob eine Taste einen Takt früher oder später ankommt, merkt der
//         C64 so wenig wie bei einer echten Tastatur.
// Takte:  Zwei Domänen — die einzige Stelle, an der sie sich berühren.
//           clk_av  Takt der Brücke (100 MHz), Reset rst_av
//           clk     Takt des C64 (31,5 MHz), Reset rst
//         Beide Resets synchron und aktiv high. rst_av darf nur zusammen mit
//         rst kommen (Einschalten). rst allein (Reset-Taster des C64) wirft
//         ein wartendes Byte weg und gibt den Briefkasten frei; die Tasten
//         bleiben, wie Linux sie gesetzt hat.
// Ports:  Seite HPS, Avalon-MM-Slave (avs_*), avs_address zählt Register:
//           0  DATA     Schreiben: Bit 7..0 = Byte für den C64. Wird
//                       ignoriert, solange belegt.
//                       Lesen: das zuletzt angenommene Byte.
//           1  STATUS   Bit 0 = 1, solange belegt (nur lesen).
//                       Bit 1 = 1: Taste RESTORE gedrückt (lesen und
//                       schreiben). Sie hat ein eigenes Bit, weil sie beim
//                       C64 nicht im Gitter hängt, sondern am NMI.
//                       Bit 12..8 = Joystick an Port 1, Bit 20..16 =
//                       Joystick an Port 2 (lesen und schreiben), je
//                       1 = betätigt: hoch, runter, links, rechts, Feuer.
//           2  KEYS_LO  Tasten 31..0, lesen und schreiben
//           3  KEYS_HI  Tasten 63..32, lesen und schreiben
//           avs_byteenable: Bei DATA muss Bit 0 gesetzt sein; so löst ein
//           Zugriff, den Linux in einzelne Bytes zerlegt, nur einmal aus.
//           Bei den Tasten und in STATUS werden nur die freigegebenen Bytes
//           geändert.
//           avs_readdatavalid kommt einen Takt nach avs_read;
//           avs_waitrequest ist immer 0. Lesen ändert nichts.
//         Seite C64:
//           valid_q = 1: data_q ist ein neues Byte und bleibt stehen, bis
//           der Abnehmer ready = 1 zeigt. In diesem Takt gilt das Byte als
//           übergeben.
//           keys_q — Tastenzustand für key_matrix.
//           restore_q — Taste RESTORE, für den NMI in soc_c64.
//           joy1_q, joy2_q — Joysticks für soc_c64.

`default_nettype none

module hps_byte_port (
    input  wire        clk_av,
    input  wire        rst_av,
    input  wire [1:0]  avs_address,
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
    input  wire        ready,
    output wire [63:0] keys_q,
    output wire        restore_q,
    output wire [4:0]  joy1_q,
    output wire [4:0]  joy2_q
);

    localparam [1:0] A_DATA    = 2'd0,
                     A_STATUS  = 2'd1,
                     A_KEYS_LO = 2'd2,
                     A_KEYS_HI = 2'd3;

    reg        req_tgl_q;   // Fähnchen der HPS-Seite (clk_av)
    reg        ack_tgl_q;   // Fähnchen der C64-Seite (clk)
    reg [7:0]  data_av_q;   // der Brief; steht still, solange belegt
    reg [63:0] keys_av_q;   // Tastenzustand, wie Linux ihn geschrieben hat
    reg        restore_av_q;
    reg [4:0]  joy1_av_q;
    reg [4:0]  joy2_av_q;

    // --- Seite HPS (clk_av) -------------------------------------------------
    wire ack_sync_q;

    sync_2ff u_sync_ack (
        .clk      (clk_av),
        .d_async  (ack_tgl_q),
        .d_sync_q (ack_sync_q)
    );

    wire busy    = (req_tgl_q != ack_sync_q);
    wire do_send = avs_write && (avs_address == A_DATA) && avs_byteenable[0] && !busy;

    assign avs_waitrequest = 1'b0;

    integer i;

    always @(posedge clk_av) begin
        if (rst_av) begin
            req_tgl_q         <= 1'b0;
            keys_av_q         <= 64'd0;
            restore_av_q      <= 1'b0;
            joy1_av_q         <= 5'd0;
            joy2_av_q         <= 5'd0;
            avs_readdatavalid <= 1'b0;
        end else begin
            if (do_send) begin
                data_av_q <= avs_writedata[7:0];
                req_tgl_q <= ~req_tgl_q;
            end

            if (avs_write && (avs_address == A_STATUS)) begin
                if (avs_byteenable[0]) restore_av_q <= avs_writedata[1];
                if (avs_byteenable[1]) joy1_av_q    <= avs_writedata[12:8];
                if (avs_byteenable[2]) joy2_av_q    <= avs_writedata[20:16];
            end

            for (i = 0; i < 4; i = i + 1) begin
                if (avs_write && avs_byteenable[i]) begin
                    if (avs_address == A_KEYS_LO) keys_av_q[i*8 +: 8]      <= avs_writedata[i*8 +: 8];
                    if (avs_address == A_KEYS_HI) keys_av_q[32 + i*8 +: 8] <= avs_writedata[i*8 +: 8];
                end
            end

            avs_readdatavalid <= avs_read;
            case (avs_address)
                A_DATA:    avs_readdata <= {24'b0, data_av_q};
                A_STATUS:  avs_readdata <= {11'b0, joy2_av_q, 3'b0, joy1_av_q, 6'b0, restore_av_q, busy};
                A_KEYS_LO: avs_readdata <= keys_av_q[31:0];
                default:   avs_readdata <= keys_av_q[63:32];
            endcase
        end
    end

    // --- Seite C64 (clk) ----------------------------------------------------
    wire req_sync_q;

    sync_2ff u_sync_req (
        .clk      (clk),
        .d_async  (req_tgl_q),
        .d_sync_q (req_sync_q)
    );

    sync_2ff #(.WIDTH(75)) u_sync_keys (
        .clk      (clk),
        .d_async  ({joy2_av_q, joy1_av_q, restore_av_q, keys_av_q}),
        .d_sync_q ({joy2_q, joy1_q, restore_q, keys_q})
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
