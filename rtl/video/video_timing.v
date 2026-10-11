// video_timing — Zeilen- und Bildzähler für das Videosignal.
//
// Zweck:  Erzeugt das Zeitraster eines Bildes. Wie beim Röhrenmonitor läuft
//         ein gedachter Strahl Zeile für Zeile über das Bild; nur ein Teil
//         davon ist sichtbar, der Rest sind Pausen (Front Porch, Sync, Back
//         Porch), in denen der Monitor den Zeilen- bzw. Bildanfang erkennt.
//         Default: 640x480 bei 60 Hz, Pixeltakt 25,175 MHz
//           Zeile: 640 sichtbar + 16 + 96 (Sync) + 48 = 800 Pixel
//           Bild:  480 sichtbar + 10 +  2 (Sync) + 33 = 525 Zeilen
// Takt:   clk, synchroner Reset rst (aktiv high). Der Strahl rückt nur in
//         Takten mit en = 1 weiter (Taktfreigabe): Pixeltakt = clk-Takte
//         mit en = 1, z. B. jeder zweite Takt von 50 MHz = 25 MHz.
// Ports:  x_q/y_q — Position des Strahls; der sichtbare Bereich beginnt bei
//         (0,0), die Pausen liegen dahinter.
//         de = 1 im sichtbaren Bereich. hsync/vsync = 1 während des
//         Sync-Impulses (hier high-aktiv; 640x480 verlangt am Stecker
//         low-aktive Impulse — das dreht das Top-Level um).

`default_nettype none

module video_timing #(
    parameter H_ACTIVE = 640,
    parameter H_FP     = 16,
    parameter H_SYNC   = 96,
    parameter H_BP     = 48,
    parameter V_ACTIVE = 480,
    parameter V_FP     = 10,
    parameter V_SYNC   = 2,
    parameter V_BP     = 33
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    output reg  [11:0] x_q,
    output reg  [11:0] y_q,
    output wire        de,
    output wire        hsync,
    output wire        vsync
);

    localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
    localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

    always @(posedge clk) begin
        if (rst) begin
            x_q <= 12'd0;
            y_q <= 12'd0;
        end else if (en) begin
            if (x_q == H_TOTAL - 1) begin
                x_q <= 12'd0;
                y_q <= (y_q == V_TOTAL - 1) ? 12'd0 : y_q + 1'b1;
            end else begin
                x_q <= x_q + 1'b1;
            end
        end
    end

    assign de    = (x_q < H_ACTIVE) && (y_q < V_ACTIVE);
    assign hsync = (x_q >= H_ACTIVE + H_FP) && (x_q < H_ACTIVE + H_FP + H_SYNC);
    assign vsync = (y_q >= V_ACTIVE + V_FP) && (y_q < V_ACTIVE + V_FP + V_SYNC);

endmodule

`default_nettype wire
