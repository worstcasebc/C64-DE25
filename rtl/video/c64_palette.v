// c64_palette — übersetzt die 16 Farbnummern des C64 in RGB.
//
// Zweck:  Der VIC-II kennt nur Farbnummern 0..15. Welche Farbe das genau
//         ist, bestimmte im Original die analoge Schaltung; hier steht dafür
//         die verbreitete Palette von "Pepto" (Philip Timmermann).
// Takt:   keiner (rein kombinatorisch).
// Ports:  color -> rgb = {Rot, Grün, Blau}, je 8 Bit.
// Test:   tb_video_scandoubler prüft die Tabelle mit.

`default_nettype none

module c64_palette (
    input  wire [3:0]  color,
    output reg  [23:0] rgb
);

    always @* begin
        case (color)
            4'd0:  rgb = 24'h000000;    // Schwarz
            4'd1:  rgb = 24'hFFFFFF;    // Weiß
            4'd2:  rgb = 24'h68372B;    // Rot
            4'd3:  rgb = 24'h70A4B2;    // Cyan
            4'd4:  rgb = 24'h6F3D86;    // Violett
            4'd5:  rgb = 24'h588D43;    // Grün
            4'd6:  rgb = 24'h352879;    // Blau
            4'd7:  rgb = 24'hB8C76F;    // Gelb
            4'd8:  rgb = 24'h6F4F25;    // Orange
            4'd9:  rgb = 24'h433900;    // Braun
            4'd10: rgb = 24'h9A6759;    // Hellrot
            4'd11: rgb = 24'h444444;    // Dunkelgrau
            4'd12: rgb = 24'h6C6C6C;    // Grau
            4'd13: rgb = 24'h9AD284;    // Hellgrün
            4'd14: rgb = 24'h6C5EB5;    // Hellblau
            4'd15: rgb = 24'h959595;    // Hellgrau
        endcase
    end

endmodule

`default_nettype wire
