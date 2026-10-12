// drive_1541 — Hülle um das Diskettenlaufwerk 1541 aus MiSTer: ein Laufwerk
//              mit der Gerätenummer 8.
//
// Zweck:  Der Core c1541_multi (rtl/drive/vendor/mister_c1541) bildet die
//         1541 samt eigener CPU, ROM und zwei VIA 6522 nach. Diese Hülle
//         reduziert ihn auf das, was der Rechner braucht, und versteckt
//         seine SystemVerilog-Schreibweisen (Felder als Anschlüsse), die
//         sich aus Verilog nicht verbinden lassen.
// Takt:   clk (eine Domäne), synchroner Reset rst (aktiv high). Das Laufwerk
//         rechnet mit 16 MHz; aus clk wird dafür eine Freigabe gemacht, die
//         bei CE_NUM von CE_DEN Takten kommt (ce_fraction). Bei 31,5 MHz
//         sind das 32 von 63.
// Ports:  Serieller Bus (siehe soc_c64, "IEC"): iec_atn_i, iec_clk_i,
//         iec_data_i — was der C64 auf die Leitungen gibt (0 = zieht);
//         iec_clk_o, iec_data_o — was das Laufwerk darauf gibt.
//         led — Leuchte des Laufwerks (1 = an).
//         Diskette: img_mounted wechselt von 0 auf 1, wenn eine Diskette
//         eingelegt oder entnommen wird; img_size = 0 heißt "keine
//         Diskette". img_readonly = Schreibschutz. gcr_mode = 0: das Abbild
//         ist eine .D64 (Sektoren zu 256 Bytes), 1: eine .G64 (Spuren, wie
//         sie auf der Diskette stehen).
//         Blöcke: Das Laufwerk fordert mit sd_rd = 1 Daten an, mit
//         sd_wr = 1 will es welche loswerden; sd_lba ist der erste Block,
//         sd_blk_cnt + 1 die Anzahl, ein Block hat 256 Bytes. Der Lieferant
//         antwortet mit sd_ack = 1, solange er überträgt: Beim Lesen legt
//         er Byte für Byte sd_buff_addr und sd_buff_dout an und gibt
//         sd_buff_wr = 1; beim Schreiben legt er sd_buff_addr an und liest
//         sd_buff_din. Mit sd_ack = 0 ist die Übertragung beendet.

`default_nettype none

module drive_1541 #(
    parameter CE_NUM = 32,
    parameter CE_DEN = 63
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        iec_atn_i,
    input  wire        iec_clk_i,
    input  wire        iec_data_i,
    output wire        iec_clk_o,
    output wire        iec_data_o,
    output wire        led,

    input  wire        img_mounted,
    input  wire        img_readonly,
    input  wire [31:0] img_size,
    input  wire        gcr_mode,

    output wire [31:0] sd_lba,
    output wire [5:0]  sd_blk_cnt,
    output wire        sd_rd,
    output wire        sd_wr,
    input  wire        sd_ack,
    input  wire [13:0] sd_buff_addr,
    input  wire [7:0]  sd_buff_dout,
    output wire [7:0]  sd_buff_din,
    input  wire        sd_buff_wr
);

    // --- Freigabe für 16 MHz ------------------------------------------------
    wire ce_q;

    ce_fraction #(.NUM(CE_NUM), .DEN(CE_DEN)) u_ce (
        .clk  (clk),
        .rst  (rst),
        .ce_q (ce_q)
    );

    // --- Das Laufwerk -------------------------------------------------------
    // Ein Laufwerk, kein Parallelkabel, ein ROM (aus der .mif-Datei).
    wire [31:0] lba      [1];
    wire [5:0]  blk_cnt  [1];
    wire [7:0]  buff_din [1];

    assign sd_lba      = lba[0];
    assign sd_blk_cnt  = blk_cnt[0];
    assign sd_buff_din = buff_din[0];

    c1541_multi #(.PARPORT(0), .DUALROM(0), .DRIVES(1)) u_c1541 (
        .clk          (clk),
        .reset        (rst),
        .ce           (ce_q),
        .pause        (1'b0),
        .gcr_mode     (gcr_mode),

        .img_mounted  (img_mounted),
        .img_readonly (img_readonly),
        .img_size     (img_size),
        .drive_rpm    (3'd0),           // 300 Umdrehungen pro Minute
        .drive_wobble (1'b0),

        .led          (led),
        .disk_ready   (),

        .iec_atn_i    (iec_atn_i),
        .iec_data_i   (iec_data_i),
        .iec_clk_i    (iec_clk_i),
        .iec_data_o   (iec_data_o),
        .iec_clk_o    (iec_clk_o),

        .par_data_i   (8'hFF),
        .par_stb_i    (1'b1),
        .par_data_o   (),
        .par_stb_o    (),

        .clk_sys      (clk),

        .sd_lba       (lba),
        .sd_blk_cnt   (blk_cnt),
        .sd_rd        (sd_rd),
        .sd_wr        (sd_wr),
        .sd_ack       (sd_ack),
        .sd_buff_addr (sd_buff_addr),
        .sd_buff_dout (sd_buff_dout),
        .sd_buff_din  (buff_din),
        .sd_buff_wr   (sd_buff_wr),

        .rom_addr     (15'd0),          // ROM wird nicht nachgeladen
        .rom_data     (8'd0),
        .rom_wr       (1'b0),
        .rom_std      (1'b1)
    );

endmodule

`default_nettype wire
