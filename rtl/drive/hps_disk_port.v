// hps_disk_port — Diskette für das Laufwerk 1541, geliefert von Linux (HPS).
//
// Zweck:  Das Laufwerk (drive_1541) hat keine Diskette, sondern fordert
//         Spuren an: "gib mir ab Block N so viele Blöcke". Dieses Modul
//         reicht die Anforderung an Linux weiter und bringt die Antwort ins
//         Laufwerk — wie eine Durchreiche zwischen Küche und Gastraum:
//           1. Das Laufwerk stellt den Bestellzettel hin (sd_rd, sd_lba,
//              sd_blk_cnt). Linux sieht ihn im Register REQUEST.
//           2. Linux füllt den Puffer (ein RAM mit einer Tür auf jeder
//              Seite, ram_2clk) und meldet in CONTROL "geliefert".
//           3. Das Modul trägt den Pufferinhalt Byte für Byte ins Laufwerk
//              (sd_ack, sd_buff_*). Solange meldet STATUS "beschäftigt".
//         Linux legt außerdem die Diskette ein und nimmt sie heraus
//         (Register MOUNT).
//         Noch nicht umgesetzt: Schreiben auf die Diskette. Schreibwünsche
//         des Laufwerks (sd_wr) werden angenommen und verworfen; Linux
//         sollte die Diskette deshalb mit Schreibschutz einlegen.
// Takte:  Zwei Domänen.
//           clk_av  Takt der Brücke (100 MHz), Reset rst_av
//           clk     Takt von C64 und Laufwerk (31,5 MHz), Reset rst
//         Beide Resets synchron und aktiv high; rst_av nur zusammen mit rst.
//         Über die Grenze gehen: die Daten durch das RAM; "geliefert" und
//         "Diskette gewechselt" als Fähnchen wie in hps_byte_port; einzelne
//         Pegel durch sync_2ff. Block und Anzahl der Anforderung liest die
//         HPS-Seite ohne Synchronizer: Sie stehen still, sobald die
//         Anforderung (zwei Takte später) sichtbar ist.
// Ports:  Seite HPS, Avalon-MM-Slave (avs_*), avs_address zählt Worte:
//           0      REQUEST  lesen: Bit 0 = Laufwerk will lesen,
//                           Bit 1 = Laufwerk will schreiben,
//                           Bit 13..8 = Anzahl Blöcke - 1,
//                           Bit 31..16 = erster Block. Während einer
//                           Lieferung lesen Bit 0 und 1 als 0.
//           1      CONTROL  schreiben, Bit 0 = 1: geliefert.
//                  STATUS   lesen, Bit 0 = 1: beschäftigt.
//           2      MOUNT    lesen und schreiben: Bit 0 = Diskette vorhanden,
//                           Bit 1 = Schreibschutz, Bit 2 = Format (0 = .D64,
//                           1 = .G64). Jedes Schreiben gilt als
//                           Diskettenwechsel.
//           2048.. PUFFER   schreiben: 8192 Bytes, vier pro Wort, das
//                           unterste zuerst. Byte 0 ist das erste der
//                           Lieferung.
//           avs_readdatavalid kommt einen Takt nach avs_read;
//           avs_waitrequest ist immer 0.
//         Seite Laufwerk: Anschlüsse wie in drive_1541 beschrieben.
//           img_present = 1: Diskette eingelegt (auch für img_size und den
//           Reset des Laufwerks gedacht).
//           img_mounted gibt bei jedem Diskettenwechsel einen Impuls.

`default_nettype none

module hps_disk_port (
    input  wire        clk_av,
    input  wire        rst_av,
    input  wire [11:0] avs_address,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire [3:0]  avs_byteenable,
    input  wire        avs_read,
    output reg  [31:0] avs_readdata,
    output reg         avs_readdatavalid,
    output wire        avs_waitrequest,

    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] sd_lba,
    input  wire [5:0]  sd_blk_cnt,
    input  wire        sd_rd,
    input  wire        sd_wr,
    output reg         sd_ack,
    output reg  [13:0] sd_buff_addr,
    output reg  [7:0]  sd_buff_dout,
    output reg         sd_buff_wr,
    output reg         img_mounted,
    output reg         img_present,
    output reg         img_readonly,
    output reg         gcr_mode
);

    localparam [10:0] A_REQUEST = 11'd0,
                      A_CONTROL = 11'd1,
                      A_MOUNT   = 11'd2;

    wire sel_buffer = avs_address[11];

    reg done_tgl_q;     // Fähnchen "geliefert" (clk_av)
    reg ack_tgl_q;      // Fähnchen "eingetragen" (clk)
    reg mount_tgl_q;    // Fähnchen "Diskette gewechselt" (clk_av)

    // --- Seite HPS (clk_av) -------------------------------------------------
    reg [2:0] mount_av_q;       // Format, Schreibschutz, vorhanden

    wire ack_sync_q;
    wire rd_sync_q;
    wire wr_sync_q;

    sync_2ff #(.WIDTH(3)) u_sync_to_av (
        .clk      (clk_av),
        .d_async  ({ack_tgl_q, sd_wr, sd_rd}),
        .d_sync_q ({ack_sync_q, wr_sync_q, rd_sync_q})
    );

    wire busy = (done_tgl_q != ack_sync_q);

    assign avs_waitrequest = 1'b0;

    always @(posedge clk_av) begin
        if (rst_av) begin
            done_tgl_q        <= 1'b0;
            mount_tgl_q       <= 1'b0;
            mount_av_q        <= 3'b000;
            avs_readdatavalid <= 1'b0;
        end else begin
            if (avs_write && !sel_buffer && avs_byteenable[0]) begin
                if (avs_address[10:0] == A_CONTROL && avs_writedata[0] && !busy) begin
                    done_tgl_q <= ~done_tgl_q;
                end
                if (avs_address[10:0] == A_MOUNT) begin
                    mount_av_q  <= avs_writedata[2:0];
                    mount_tgl_q <= ~mount_tgl_q;
                end
            end

            avs_readdatavalid <= avs_read;
            if (sel_buffer) begin
                avs_readdata <= 32'd0;
            end else begin
                case (avs_address[10:0])
                    A_REQUEST: avs_readdata <= {sd_lba[15:0], 2'b00, sd_blk_cnt, 6'b000000,
                                                wr_sync_q & ~busy, rd_sync_q & ~busy};
                    A_CONTROL: avs_readdata <= {31'b0, busy};
                    A_MOUNT:   avs_readdata <= {29'b0, mount_av_q};
                    default:   avs_readdata <= 32'd0;
                endcase
            end
        end
    end

    // --- Puffer: vier Byte-Spuren, eine je Byte des Datenworts --------------
    reg  [12:0] idx_q;          // Nummer des Bytes, das gerade eingetragen wird
    wire [7:0]  lane [0:3];

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : g_lane
            ram_2clk #(.ADDR_W(11), .DATA_W(8)) u_ram (
                .wr_clk    (clk_av),
                .wr_en     (avs_write && sel_buffer && avs_byteenable[g]),
                .wr_addr   (avs_address[10:0]),
                .wr_din    (avs_writedata[g*8 +: 8]),
                .rd_clk    (clk),
                .rd_addr   (idx_q[12:2]),
                .rd_dout_q (lane[g])
            );
        end
    endgenerate

    // --- Seite Laufwerk (clk) -----------------------------------------------
    wire       done_sync_q;
    wire       mount_sync_q;
    wire [2:0] mount_lvl_q;

    sync_2ff #(.WIDTH(5)) u_sync_to_drive (
        .clk      (clk),
        .d_async  ({mount_av_q, mount_tgl_q, done_tgl_q}),
        .d_sync_q ({mount_lvl_q, mount_sync_q, done_sync_q})
    );

    // Diskettenwechsel: Pegel übernehmen, dann ein Impuls auf img_mounted.
    // Die Pegel kommen durch denselben Synchronizer wie das Fähnchen, können
    // aber einen Takt später ankommen — deshalb erst zwei Takte warten.
    reg       mount_seen_q;
    reg [4:0] mount_cnt_q;      // 0 = Ruhe

    always @(posedge clk) begin
        if (rst) begin
            mount_seen_q <= mount_sync_q;
            mount_cnt_q  <= 5'd0;
            img_mounted  <= 1'b0;
            {gcr_mode, img_readonly, img_present} <= mount_lvl_q;
        end else if (mount_cnt_q == 5'd0) begin
            img_mounted <= 1'b0;
            if (mount_sync_q != mount_seen_q) begin
                mount_seen_q <= mount_sync_q;
                mount_cnt_q  <= 5'd1;
            end
        end else begin
            mount_cnt_q <= mount_cnt_q + 1'b1;      // läuft bis 31 und zurück auf 0
            if (mount_cnt_q == 5'd3) {gcr_mode, img_readonly, img_present} <= mount_lvl_q;
            if (mount_cnt_q == 5'd8) img_mounted <= 1'b1;
        end
    end

    // Lieferung eintragen. Pro Byte drei Takte: Adresse ans RAM, Byte samt
    // Schreibimpuls ans Laufwerk, Byte noch einen Takt halten (das Laufwerk
    // übernimmt die Daten einen Takt nach dem Impuls).
    localparam [2:0] S_IDLE = 3'd0,
                     S_ADDR = 3'd1,
                     S_LOAD = 3'd2,
                     S_HOLD = 3'd3,
                     S_END  = 3'd4;

    reg [2:0]  state_q;
    reg [13:0] total_q;         // Bytes der Lieferung
    reg [2:0]  end_cnt_q;

    always @(posedge clk) begin
        if (rst) begin
            // Fähnchen nachziehen: Was unterwegs ist, gilt als erledigt.
            state_q    <= S_IDLE;
            ack_tgl_q  <= done_sync_q;
            sd_ack     <= 1'b0;
            sd_buff_wr <= 1'b0;
        end else begin
            sd_buff_wr <= 1'b0;

            case (state_q)
                S_IDLE: begin
                    if (done_sync_q != ack_tgl_q) begin
                        idx_q     <= 13'd0;
                        total_q   <= {8'd0, sd_blk_cnt} * 14'd256 + 14'd256;
                        end_cnt_q <= 3'd0;
                        if (sd_rd) begin
                            sd_ack  <= 1'b1;
                            state_q <= S_ADDR;
                        end else if (sd_wr) begin
                            sd_ack  <= 1'b1;        // annehmen und verwerfen
                            state_q <= S_END;
                        end else begin
                            ack_tgl_q <= ~ack_tgl_q;    // nichts bestellt
                        end
                    end
                end

                S_ADDR: state_q <= S_LOAD;

                S_LOAD: begin
                    sd_buff_addr <= {1'b0, idx_q};
                    sd_buff_dout <= lane[idx_q[1:0]];
                    sd_buff_wr   <= 1'b1;
                    state_q      <= S_HOLD;
                end

                S_HOLD: begin
                    idx_q   <= idx_q + 1'b1;
                    state_q <= ({1'b0, idx_q} + 14'd1 == total_q) ? S_END : S_ADDR;
                end

                S_END: begin
                    end_cnt_q <= end_cnt_q + 1'b1;
                    if (end_cnt_q == 3'd3) sd_ack <= 1'b0;
                    if (end_cnt_q == 3'd7) begin
                        ack_tgl_q <= ~ack_tgl_q;
                        state_q   <= S_IDLE;
                    end
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
