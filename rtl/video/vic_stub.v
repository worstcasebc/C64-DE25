// vic_stub — Platzhalter für den VIC-II: nur die beiden Farbregister.
//
// Zweck:  Bis der echte VIC-II kommt (Meilenstein 5), gibt es von seinen 47
//         Registern nur zwei:
//           $D020  Rahmenfarbe       (4 Bit)
//           $D021  Hintergrundfarbe  (4 Bit)
//         Alle anderen lesen $00 — wichtig für das Original-KERNAL, das beim
//         Start wartet, bis das Raster-Register $D012 den Wert 0 hat.
//         Wie beim echten Chip wiederholen sich die Register alle 64
//         Adressen im Bereich $D000-$D3FF, und die oberen vier Bits der
//         Farbregister lesen als 1.
// Takt:   clk, synchroner Reset rst (aktiv high). Buszugriffe nur bei en = 1.
// Bus:    sel = 1 bei $D000-$D3FF, addr = untere 6 Adressbits. Lesedaten
//         liegen wie beim RAM einen Schritt später an dout_q an.
// Ports:  border_color_q/bg_color_q — Farbnummern 0..15 für video_text.

`default_nettype none

module vic_stub (
    input  wire       clk,
    input  wire       rst,
    input  wire       en,
    input  wire       sel,
    input  wire       we,
    input  wire [5:0] addr,
    input  wire [7:0] din,
    output reg  [7:0] dout_q,
    output reg  [3:0] border_color_q,
    output reg  [3:0] bg_color_q
);

    localparam [5:0] REG_BORDER = 6'h20,
                     REG_BG     = 6'h21;

    always @(posedge clk) begin
        if (rst) begin
            border_color_q <= 4'd0;
            bg_color_q     <= 4'd0;
        end else if (en && sel && we) begin
            if (addr == REG_BORDER) border_color_q <= din[3:0];
            if (addr == REG_BG)     bg_color_q     <= din[3:0];
        end
    end

    always @(posedge clk) begin
        if (en) begin
            case (addr)
                REG_BORDER: dout_q <= {4'hF, border_color_q};
                REG_BG:     dout_q <= {4'hF, bg_color_q};
                default:    dout_q <= 8'h00;
            endcase
        end
    end

endmodule

`default_nettype wire
