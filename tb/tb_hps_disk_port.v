// tb_hps_disk_port — selbstprüfende Testbench für hps_disk_port.
//
// Zwei Takte ohne festes Verhältnis: clk_av 100 MHz, clk 31,5 MHz. Die Tasks
// av_write/av_read spielen Linux an der Brücke; ein kleines Modell spielt das
// Laufwerk: Es nimmt seine Anforderung zurück, sobald sd_ack kommt, und
// merkt sich jedes Byte, das mit sd_buff_wr eintrifft. Geprüft wird:
//   1. Nach dem Reset: keine Anforderung, keine Diskette, nicht beschäftigt.
//   2. Einlegen: Die Pegel aus MOUNT erscheinen beim Laufwerk, und
//      img_mounted gibt genau einen Impuls — erst nachdem die Pegel stehen.
//   3. Leseanforderung: Block und Anzahl stehen in REQUEST.
//   4. Lieferung: genau die Bytes aus dem Puffer, in der Reihenfolge, jedes
//      mit sd_ack = 1 und noch einen Takt gehalten; danach fällt sd_ack und
//      "beschäftigt" endet. Währenddessen zeigt REQUEST keine Anforderung.
//   5. Eine zweite Lieferung mit anderer Länge und nur teilweise neu
//      beschriebenem Puffer (byteenable).
//   6. Schreibwunsch des Laufwerks: Das Modul holt die Spur von sich aus ab
//      (genau so viele Bytes, wie die Spur hat) und meldet sie in REQUEST.
//      Block und Anzahl bleiben stehen, auch wenn das Laufwerk inzwischen
//      weiterzieht und schon wieder lesen will. Linux liest die Bytes
//      richtig aus dem Puffer; nach "abgeholt" kommt die Leseanforderung.
//   7. "Geliefert" ohne Anforderung bleibt folgenlos.
//   8. Reset des C64 mitten in der Lieferung: sd_ack fällt, der Port ist
//      danach frei; die eingelegte Diskette bleibt.
//   9. Laufwerk ein und aus (MOUNT Bit 3) ist unabhängig von der Diskette:
//      Beim Herausnehmen und Einlegen bleibt es an.

`timescale 1ns / 1ps
`default_nettype none

module tb_hps_disk_port;

    localparam [11:0] REQUEST = 12'd0,
                      CONTROL = 12'd1,
                      MOUNT   = 12'd2,
                      BUFFER  = 12'd2048;

    reg         clk_av = 1'b0;
    reg         rst_av = 1'b1;
    reg  [11:0] av_address = 12'd0;
    reg         av_write_r = 1'b0;
    reg  [31:0] av_writedata = 32'd0;
    reg  [3:0]  av_byteenable = 4'b0000;
    reg         av_read_r = 1'b0;
    wire [31:0] av_readdata;
    wire        av_readdatavalid;
    wire        av_waitrequest;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [31:0] sd_lba = 32'd0;
    reg  [5:0]  sd_blk_cnt = 6'd0;
    reg         sd_rd = 1'b0;
    reg         sd_wr = 1'b0;
    wire        sd_ack;
    wire [13:0] sd_buff_addr;
    wire [7:0]  sd_buff_dout;
    wire        sd_buff_wr;
    wire        img_mounted;
    wire        img_present;
    wire        img_readonly;
    wire        gcr_mode;
    wire        drive_on;

    integer     errors = 0;
    integer     i;
    reg [31:0]  rd;

    hps_disk_port dut (
        .clk_av            (clk_av),
        .rst_av            (rst_av),
        .avs_address       (av_address),
        .avs_write         (av_write_r),
        .avs_writedata     (av_writedata),
        .avs_byteenable    (av_byteenable),
        .avs_read          (av_read_r),
        .avs_readdata      (av_readdata),
        .avs_readdatavalid (av_readdatavalid),
        .avs_waitrequest   (av_waitrequest),
        .clk               (clk),
        .rst               (rst),
        .sd_lba            (sd_lba),
        .sd_blk_cnt        (sd_blk_cnt),
        .sd_rd             (sd_rd),
        .sd_wr             (sd_wr),
        .sd_ack            (sd_ack),
        .sd_buff_addr      (sd_buff_addr),
        .sd_buff_dout      (sd_buff_dout),
        .sd_buff_din       (sd_buff_din),
        .sd_buff_wr        (sd_buff_wr),
        .img_mounted       (img_mounted),
        .img_present       (img_present),
        .img_readonly      (img_readonly),
        .gcr_mode          (gcr_mode),
        .drive_on          (drive_on)
    );

    always #5      clk_av = ~clk_av;   // 100 MHz
    always #15.873 clk    = ~clk;      // 31,5 MHz

    // --- Modell des Laufwerks ----------------------------------------------
    reg [7:0] got [0:8191];     // eingetroffene Bytes nach Adresse
    integer   n_bytes = 0;      // Schreibimpulse seit dem letzten Löschen
    integer   n_mount = 0;      // Impulse auf img_mounted
    integer   n_order = 0;      // Bytes, die nicht in der Reihenfolge kamen
    reg       mounted_old = 1'b0;
    reg       want_present = 1'b0;    // Pegel, den der nächste Impuls antreffen muss
    reg       wr_old = 1'b0;
    reg [13:0] addr_old;
    reg [7:0]  data_old;

    // Spurpuffer des Laufwerks beim Abholen: Die Daten kommen zwei Takte
    // nach der Adresse, wie beim Speicher im echten Core.
    function [7:0] track_byte(input integer k);
        track_byte = (k * 13 + 5 + (k >> 8)) & 8'hFF;
    endfunction

    reg [13:0] din_addr_q;
    reg [7:0]  sd_buff_din;

    always @(posedge clk) begin
        din_addr_q  <= sd_buff_addr;
        sd_buff_din <= track_byte(din_addr_q);
    end
    always @(posedge clk) begin
        if (sd_ack) {sd_rd, sd_wr} <= 2'b00;    // wie c1541_track

        mounted_old <= img_mounted;
        if (img_mounted && !mounted_old) begin
            n_mount = n_mount + 1;
            if (img_present !== want_present) begin
                $display("FAIL: img_mounted, bevor der Pegel img_present steht, t=%0t", $time);
                errors = errors + 1;
            end
        end

        if (sd_buff_wr) begin
            if (!sd_ack) begin
                $display("FAIL: sd_buff_wr ohne sd_ack, t=%0t", $time);
                errors = errors + 1;
            end
            if (sd_buff_addr !== n_bytes[13:0]) n_order = n_order + 1;
            n_bytes = n_bytes + 1;
        end

        // Das Laufwerk übernimmt die Daten einen Takt nach dem Impuls.
        wr_old   <= sd_buff_wr;
        addr_old <= sd_buff_addr;
        data_old <= sd_buff_dout;
        if (wr_old) begin
            got[addr_old[12:0]] = sd_buff_dout;
            if (sd_buff_dout !== data_old || sd_buff_addr !== addr_old) begin
                $display("FAIL: Byte nicht einen Takt gehalten, t=%0t", $time);
                errors = errors + 1;
            end
        end
    end

    always @(posedge clk_av) begin
        if (av_waitrequest !== 1'b0) begin
            $display("FAIL: waitrequest ist nicht 0 bei t=%0t", $time);
            errors = errors + 1;
        end
    end

    task expect_eq(input integer got_v, input integer want, input [255:0] what);
        begin
            if (got_v !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got_v, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    task av_write(input [11:0] addr, input [31:0] value, input [3:0] be);
        begin
            @(negedge clk_av);
            av_address    = addr;
            av_writedata  = value;
            av_byteenable = be;
            av_write_r    = 1'b1;
            @(negedge clk_av);
            av_write_r    = 1'b0;
        end
    endtask

    task av_read(input [11:0] addr, output [31:0] value);
        begin
            @(negedge clk_av);
            av_address = addr;
            av_read_r  = 1'b1;
            @(negedge clk_av);
            av_read_r  = 1'b0;
            expect_eq(av_readdatavalid, 1, "readdatavalid einen Takt nach read");
            value = av_readdata;
        end
    endtask

    // Byte k einer Lieferung mit dem Kennzeichen seed
    function [7:0] pattern(input integer k, input integer seed);
        pattern = (k * 7 + seed + (k >> 8)) & 8'hFF;
    endfunction

    // Linux: Puffer füllen (vier Bytes pro Wort, das unterste zuerst)
    task fill_buffer(input integer n_bytes_total, input integer seed);
        integer w;
        begin
            for (w = 0; w < n_bytes_total / 4; w = w + 1) begin
                av_write(BUFFER + w[11:0],
                         {pattern(4*w+3, seed), pattern(4*w+2, seed), pattern(4*w+1, seed), pattern(4*w, seed)},
                         4'b1111);
            end
        end
    endtask

    // Linux: "geliefert" melden und warten, bis nicht mehr beschäftigt
    task commit_and_wait;
        integer tries;
        reg [31:0] st;
        begin
            av_write(CONTROL, 32'd1, 4'b1111);
            av_read(CONTROL, st);
            expect_eq(st[0], 1, "beschaeftigt direkt nach geliefert");
            av_read(REQUEST, st);
            expect_eq(st[1:0], 0, "REQUEST zeigt waehrend der Lieferung nichts");
            tries = 0;
            while (st[0] !== 1'b0 || tries == 0) begin
                av_read(CONTROL, st);
                tries = tries + 1;
                if (tries > 200000) begin
                    $display("FAIL: bleibt beschaeftigt");
                    errors = errors + 1;
                    st = 32'd0;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("tb/build/tb_hps_disk_port.vcd");
        $dumpvars(0, tb_hps_disk_port);

        repeat (6) @(posedge clk);
        @(negedge clk_av) rst_av = 1'b0;
        @(negedge clk)    rst    = 1'b0;
        repeat (4) @(posedge clk);

        // 1. nach dem Reset
        av_read(REQUEST, rd);
        expect_eq(rd[1:0], 0, "1. keine Anforderung");
        av_read(CONTROL, rd);
        expect_eq(rd, 0, "1. nicht beschaeftigt");
        av_read(MOUNT, rd);
        expect_eq(rd, 0, "1. MOUNT");
        expect_eq({gcr_mode, img_readonly, img_present, img_mounted, sd_ack}, 0, "1. Ausgaenge");

        // 2. Diskette einlegen: vorhanden, Schreibschutz, .D64
        want_present = 1'b1;
        av_write(MOUNT, 32'h0000_0003, 4'b1111);
        repeat (50) @(negedge clk);
        expect_eq({gcr_mode, img_readonly, img_present}, 3'b011, "2. Pegel nach dem Einlegen");
        expect_eq(n_mount, 1, "2. ein Impuls auf img_mounted");
        expect_eq(img_mounted, 0, "2. Impuls ist vorbei");
        av_read(MOUNT, rd);
        expect_eq(rd, 3, "2. MOUNT zuruecklesen");

        // 3. Leseanforderung: Spur 18 einer .D64
        @(negedge clk);
        sd_lba     = 32'd357;
        sd_blk_cnt = 6'd18;
        sd_rd      = 1'b1;
        repeat (4) @(negedge clk);
        av_read(REQUEST, rd);
        expect_eq(rd[1:0], 2'b01, "3. Leseanforderung sichtbar");
        expect_eq(rd[13:8], 18, "3. Anzahl - 1");
        expect_eq(rd[31:16], 357, "3. erster Block");

        // 4. liefern
        fill_buffer(19 * 256, 3);
        n_bytes = 0;
        commit_and_wait;
        expect_eq(sd_ack, 0, "4. sd_ack nach der Lieferung");
        expect_eq(sd_rd, 0, "4. Anforderung zurueckgenommen");
        expect_eq(n_bytes, 19 * 256, "4. Anzahl Bytes");
        expect_eq(n_order, 0, "4. Reihenfolge");
        for (i = 0; i < 19 * 256; i = i + 1) begin
            if (got[i] !== pattern(i, 3)) begin
                if (errors < 20) $display("FAIL: 4. Byte %0d ist %02x, erwartet %02x", i, got[i], pattern(i, 3));
                errors = errors + 1;
            end
        end
        av_read(REQUEST, rd);
        expect_eq(rd[1:0], 0, "4. keine Anforderung mehr");

        // 5. zweite Lieferung: ganze .G64-Spur (32 Bloecke); vom Puffer wird
        //    nur ein Byte neu geschrieben, der Rest steht noch von eben
        @(negedge clk);
        sd_lba     = 32'd36;
        sd_blk_cnt = 6'd31;
        sd_rd      = 1'b1;
        repeat (4) @(negedge clk);
        av_read(REQUEST, rd);
        expect_eq(rd, {16'd36, 2'b00, 6'd31, 6'd0, 2'b01}, "5. REQUEST");
        av_write(BUFFER + 12'd1, 32'hAABB_CCDD, 4'b0100);   // nur Byte 6
        n_bytes = 0;
        n_order = 0;
        commit_and_wait;
        expect_eq(n_bytes, 8192, "5. Anzahl Bytes");
        expect_eq(n_order, 0, "5. Reihenfolge");
        expect_eq(got[6], 8'hBB, "5. einzeln geschriebenes Byte");
        expect_eq(got[5], pattern(5, 3), "5. Nachbar davor unveraendert");
        expect_eq(got[7], pattern(7, 3), "5. Nachbar danach unveraendert");
        expect_eq(got[4863], pattern(4863, 3), "5. letztes Byte von eben");

        // 6. Schreibwunsch des Laufwerks: Spur 18 einer .D64
        @(negedge clk);
        sd_lba     = 32'd357;
        sd_blk_cnt = 6'd18;
        sd_wr      = 1'b1;
        n_bytes = 0;
        rd = 32'd0;
        for (i = 0; i < 100000 && !rd[1]; i = i + 1) av_read(REQUEST, rd);
        expect_eq(rd[1:0], 2'b10, "6. Spur liegt zum Abholen bereit");
        expect_eq(sd_wr, 0, "6. Schreibwunsch quittiert");
        expect_eq(sd_ack, 0, "6. sd_ack nach dem Abholen");
        expect_eq(n_bytes, 0, "6. nichts ins Laufwerk geschrieben");
        // das Laufwerk zieht weiter und will die nächste Spur lesen
        @(negedge clk);
        sd_lba     = 32'd376;
        sd_blk_cnt = 6'd20;
        sd_rd      = 1'b1;
        repeat (6) @(negedge clk);
        av_read(REQUEST, rd);
        expect_eq(rd, {16'd357, 2'b00, 6'd18, 6'd0, 2'b10}, "6. REQUEST bleibt bei der geschriebenen Spur");
        for (i = 0; i < 19 * 64; i = i + 1) begin
            av_read(BUFFER + i[11:0], rd);
            if (rd !== {track_byte(4*i+3), track_byte(4*i+2), track_byte(4*i+1), track_byte(4*i)}) begin
                if (errors < 20) $display("FAIL: 6. Wort %0d ist %08x", i, rd);
                errors = errors + 1;
            end
        end
        commit_and_wait;
        av_read(REQUEST, rd);
        expect_eq(rd, {16'd376, 2'b00, 6'd20, 6'd0, 2'b01}, "6. danach die Leseanforderung");
        fill_buffer(21 * 256, 9);
        commit_and_wait;
        expect_eq(n_bytes, 21 * 256, "6. Lieferung nach dem Abholen");
        expect_eq(got[5375], pattern(5375, 9), "6. letztes Byte der Lieferung");
        n_bytes = 0;

        // 7. geliefert ohne Anforderung
        commit_and_wait;
        expect_eq(sd_ack, 0, "7. sd_ack ohne Anforderung");
        expect_eq(n_bytes, 0, "7. keine Daten ohne Anforderung");

        // 8. Reset des C64 mitten in der Lieferung
        @(negedge clk);
        n_order = 0;
        sd_rd = 1'b1;
        repeat (4) @(negedge clk);
        av_write(CONTROL, 32'd1, 4'b1111);
        repeat (200) @(negedge clk);
        expect_eq(sd_ack, 1, "8. Lieferung laeuft");
        rst = 1'b1;
        repeat (4) @(negedge clk);
        expect_eq(sd_ack, 0, "8. sd_ack im Reset");
        rst = 1'b0;
        repeat (8) @(negedge clk);
        av_read(CONTROL, rd);
        expect_eq(rd, 0, "8. frei nach dem Reset");
        expect_eq(img_present, 1, "8. Diskette bleibt eingelegt");
        expect_eq(n_mount, 1, "8. kein weiterer Impuls auf img_mounted");

        // 9. Laufwerk ein und aus, unabhängig von der Diskette
        expect_eq(drive_on, 0, "9. Laufwerk bisher aus");
        av_write(MOUNT, 32'h0000_000B, 4'b1111);    // ein, Diskette, Schreibschutz
        repeat (50) @(negedge clk);
        expect_eq({drive_on, gcr_mode, img_readonly, img_present}, 4'b1011, "9. eingeschaltet mit Diskette");
        expect_eq(n_mount, 2, "9. Impuls beim Einschalten");
        want_present = 1'b0;
        av_write(MOUNT, 32'h0000_0008, 4'b1111);    // Diskette heraus, Laufwerk bleibt an
        repeat (50) @(negedge clk);
        expect_eq(img_present, 0, "9. Diskette herausgenommen");
        expect_eq(drive_on, 1, "9. Laufwerk bleibt an");
        expect_eq(n_mount, 3, "9. Impuls auch beim Herausnehmen");
        av_read(MOUNT, rd);
        expect_eq(rd, 8, "9. MOUNT zuruecklesen");
        want_present = 1'b1;
        av_write(MOUNT, 32'h0000_0009, 4'b1111);    // andere Diskette hinein
        repeat (50) @(negedge clk);
        expect_eq({drive_on, img_present}, 2'b11, "9. neue Diskette, Laufwerk weiter an");
        expect_eq(n_mount, 4, "9. Impuls beim Einlegen");
        want_present = 1'b0;
        av_write(MOUNT, 32'd0, 4'b1111);            // alles aus
        repeat (50) @(negedge clk);
        expect_eq({drive_on, img_present}, 2'b00, "9. Laufwerk aus");

        if (errors == 0) $display("PASS: tb_hps_disk_port");
        else             $display("FAIL: tb_hps_disk_port (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: tb_hps_disk_port Timeout");
        $finish;
    end

endmodule

`default_nettype wire
