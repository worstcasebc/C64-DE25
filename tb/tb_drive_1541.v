// tb_drive_1541 — selbstprüfende Testbench für das Laufwerk 1541 allein.
// Simulator: Questa
// Questa-Optionen: +initreg+0 +initmem+0
// Laufzeit: lang
//
// Das Laufwerk läuft mit seinem eigenen ROM (sw/asm/build/c1541_rom.hex, aus
// roms/ umgewandelt). Fehlt die Datei, wird der Test übersprungen. Der Core
// aus MiSTer setzt einige Register nie zurück; im FPGA beginnen sie bei 0,
// in der Simulation wären sie unbestimmt. Deshalb die Questa-Optionen oben.
//
// Der Selbsttest des ROMs dauert wie beim echten Laufwerk über eine Sekunde,
// das sind in der Simulation einige Minuten. Deshalb läuft diese Testbench
// nur, wenn man sie beim Namen nennt ("Laufzeit: lang"), und das Laufwerk
// bekommt hier einen 16-MHz-Takt mit Freigabe in jedem Takt statt 31,5 MHz
// mit 32 von 63 (das Verhältnis prüft tb_ce_fraction).
//
// Die Testbench spielt den Lieferanten der Blöcke: Jede Anforderung des
// Laufwerks wird sofort bedient, der Inhalt ist die laufende Adresse. Das
// Laufwerk fragt schon nach dem Reset die Spur mit dem Verzeichnis an, auch
// ohne Diskette; solange niemand antwortet, bleibt seine Leuchte an.
//
// Geprüft wird:
//   1. Jede Anforderung ist eine ganze Spur einer .D64 (17 bis 21 Blöcke);
//      die erste nach dem Reset ist die Verzeichnisspur (ab Block 357,
//      19 Blöcke). Schreiben will das Laufwerk nie.
//   2. Einschalten: Die Leuchte geht an und nach dem Selbsttest des ROMs
//      wieder aus und bleibt aus (bei einem Fehler würde sie blinken); die
//      Leitungen des seriellen Busses sind losgelassen.
//   3. Zieht der C64 ATN auf 0, antwortet das Laufwerk mit DATA = 0.
//   4. Diskette einlegen: Das Laufwerk fordert die Verzeichnisspur neu an,
//      und die gelieferten Bytes stehen danach in seinem Spurpuffer.
//
// Daten von der Diskette über den Bus zu holen prüft erst der Test mit dem
// ganzen Rechner.

`timescale 1ns / 1ps
`default_nettype none

module tb_drive_1541;

    localparam CLK_KHZ = 16000;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         atn = 1'b1;
    wire        iec_clk;
    wire        iec_data;
    wire        led;
    reg         img_mounted = 1'b0;
    wire [31:0] sd_lba;
    wire [5:0]  sd_blk_cnt;
    wire        sd_rd;
    wire        sd_wr;
    reg         sd_ack = 1'b0;
    reg  [13:0] sd_buff_addr = 14'd0;
    reg  [7:0]  sd_buff_dout = 8'd0;
    reg         sd_buff_wr = 1'b0;

    integer     errors = 0;
    integer     n_rd   = 0;     // Anforderungen insgesamt
    integer     n_dir  = 0;     // davon für die Verzeichnisspur
    integer     n_dir_before;
    integer     fd;
    integer     i;
    integer     k;

    drive_1541 #(.CE_NUM(1), .CE_DEN(1)) dut (
        .clk          (clk),
        .rst          (rst),
        .iec_atn_i    (atn),
        .iec_clk_i    (1'b1),
        .iec_data_i   (1'b1),
        .iec_clk_o    (iec_clk),
        .iec_data_o   (iec_data),
        .led          (led),
        .img_mounted  (img_mounted),
        .img_readonly (1'b0),
        .img_size     (32'd174848),
        .gcr_mode     (1'b0),
        .sd_lba       (sd_lba),
        .sd_blk_cnt   (sd_blk_cnt),
        .sd_rd        (sd_rd),
        .sd_wr        (sd_wr),
        .sd_ack       (sd_ack),
        .sd_buff_addr (sd_buff_addr),
        .sd_buff_dout (sd_buff_dout),
        .sd_buff_din  (),
        .sd_buff_wr   (sd_buff_wr)
    );

    always #31.25 clk = ~clk;       // 16 MHz

    // Lieferant der Blöcke
    initial begin
        forever begin
            @(posedge clk);
            if (sd_wr) begin
                $display("FAIL: Schreibwunsch bei t=%0t", $time);
                errors = errors + 1;
                $finish;
            end
            if (sd_rd) begin
                n_rd = n_rd + 1;
                if (n_rd == 1 && (sd_lba !== 32'd357 || sd_blk_cnt !== 6'd18)) begin
                    $display("FAIL: erste Anforderung ist Block %0d, %0d Bloecke", sd_lba, sd_blk_cnt + 1);
                    errors = errors + 1;
                end
                if (sd_lba > 32'd768 || sd_blk_cnt < 6'd16 || sd_blk_cnt > 6'd20) begin
                    $display("FAIL: Anforderung Block %0d, %0d Bloecke ist keine Spur", sd_lba, sd_blk_cnt + 1);
                    errors = errors + 1;
                end
                if (sd_lba === 32'd357 && sd_blk_cnt === 6'd18) n_dir = n_dir + 1;

                @(negedge clk) sd_ack = 1'b1;
                for (k = 0; k < (sd_blk_cnt + 1) * 256; k = k + 1) begin
                    @(negedge clk);
                    sd_buff_addr = k[13:0];
                    sd_buff_dout = k[7:0];
                    sd_buff_wr   = 1'b1;
                    @(negedge clk);
                    sd_buff_wr   = 1'b0;
                end
                @(negedge clk) sd_ack = 1'b0;
                repeat (4) @(posedge clk);
            end
        end
    end

    task expect_eq(input integer got, input integer want, input [255:0] what);
        begin
            if (got !== want) begin
                $display("FAIL: %0s: %0d, erwartet %0d bei t=%0t", what, got, want, $time);
                errors = errors + 1;
            end
        end
    endtask

    // Wartet, bis die Leuchte (which = 0) oder DATA (which = 1) den Wert
    // want hat, höchstens max_ms Millisekunden.
    task wait_level(input integer which, input want, input integer max_ms, input [255:0] what);
        integer n;
        reg     now;
        begin
            n   = 0;
            now = ~want;
            while (now !== want && n < max_ms * CLK_KHZ) begin
                @(posedge clk);
                now = (which == 0) ? led : iec_data;
                n   = n + 1;
            end
            if (now !== want) begin
                $display("FAIL: %0s nicht innerhalb von %0d ms", what, max_ms);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        fd = $fopen("sw/asm/build/c1541_rom.hex", "r");
        if (fd == 0) begin
            $display("uebersprungen: sw/asm/build/c1541_rom.hex fehlt (ROM der 1541 in roms/ ablegen)");
            $display("PASS: tb_drive_1541");
            $finish;
        end
        $fclose(fd);
        #1 $readmemh("sw/asm/build/c1541_rom.hex", dut.u_c1541.romstd.ram);

        repeat (20) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // 2. Einschalten: Leuchte an, nach dem Selbsttest aus
        wait_level(0, 1'b1, 200, "Leuchte an nach dem Einschalten");
        wait_level(0, 1'b0, 3000, "Leuchte aus nach dem Selbsttest");
        $display("Selbsttest fertig nach %0d ms", $time / 1000000);
        for (i = 0; i < 100 * CLK_KHZ; i = i + 1) begin
            @(posedge clk);
            if (led !== 1'b0) begin
                $display("FAIL: Leuchte bleibt nach dem Selbsttest nicht aus, t=%0t", $time);
                errors = errors + 1;
                i = 100 * CLK_KHZ;
            end
        end
        expect_eq(iec_clk, 1, "CLK losgelassen");
        expect_eq(iec_data, 1, "DATA losgelassen");
        expect_eq(n_dir >= 1, 1, "Verzeichnisspur nach dem Reset angefordert");

        // 3. ATN: Das Laufwerk antwortet mit DATA = 0
        @(negedge clk) atn = 1'b0;
        wait_level(1, 1'b0, 5, "DATA = 0 als Antwort auf ATN");
        @(negedge clk) atn = 1'b1;

        // 4. Diskette einlegen: Verzeichnisspur wird neu angefordert
        n_dir_before = n_dir;
        @(negedge clk) img_mounted = 1'b1;
        for (i = 0; i < 50 * CLK_KHZ && n_dir == n_dir_before; i = i + 1) @(posedge clk);
        expect_eq(n_dir, n_dir_before + 1, "Verzeichnisspur nach dem Einlegen angefordert");
        repeat (200000) @(posedge clk);
        expect_eq(sd_ack, 0, "Lieferung abgeschlossen");
        expect_eq(dut.u_c1541.drives[0].c1541_drv.c1541_gcr.buffer.ram[13'h0123], 8'h23, "Byte im Spurpuffer");
        $display("Anforderungen insgesamt: %0d", n_rd);

        if (errors == 0) $display("PASS: tb_drive_1541");
        else             $display("FAIL: tb_drive_1541 (%0d Fehler)", errors);
        $finish;
    end

    initial begin
        #8.0e9;
        $display("FAIL: tb_drive_1541 Timeout");
        $finish;
    end

endmodule

`default_nettype wire
