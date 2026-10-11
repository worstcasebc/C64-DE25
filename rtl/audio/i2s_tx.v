// i2s_tx — sendet Stereo-Ton als I2S-Signal (16 Bit) samt Tontakt MCLK.
//
// Zweck:  I2S ist die übliche Verbindung für digitalen Ton zwischen
//         Bausteinen:
//           MCLK   Grundtakt für den Empfänger, hier 128 je Abtastwert-Paar
//           SCLK   Bittakt, 64 je Abtastwert-Paar (= MCLK / 2)
//           LRCLK  0 = linker Kanal, 1 = rechter Kanal
//           SDATA  die Bits, höchstes zuerst, ein SCLK-Takt nach dem
//                  Wechsel von LRCLK
//         Die Leitungen wechseln mit der fallenden Flanke von SCLK; der
//         Empfänger (hier der HDMI-Sender ADV7513) übernimmt sie mit der
//         steigenden. Von den 32 Bitplätzen je Kanal werden 16 benutzt, der
//         Rest ist 0.
// Takt:   clk, synchroner Reset rst (aktiv high). Alle Tontakte entstehen
//         durch glattes Teilen: MCLK = clk / MCLK_DIV, SCLK = MCLK / 2,
//         LRCLK = SCLK / 64. Mit 31,5 MHz und MCLK_DIV = 5 sind das
//         6,3 MHz, 3,15 MHz und 49219 Abtastwerte pro Sekunde — 2,5 % über
//         den üblichen 48000. Die Tonhöhe stimmt trotzdem, weil genau so
//         viele Werte gesendet wie abgetastet werden; nur der Empfänger
//         muss die leicht abweichende Rate annehmen.
// Ports:  left/right — Abtastwerte mit Vorzeichen; sie werden am Anfang
//         jedes Paars übernommen und müssen nicht synchron dazu wechseln.
//         mclk_q, sclk_q, lrclk_q, sdata_q — die vier Leitungen.

`default_nettype none

module i2s_tx #(
    parameter MCLK_DIV = 5
) (
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] left,
    input  wire signed [15:0] right,
    output reg                mclk_q,
    output reg                sclk_q,
    output reg                lrclk_q,
    output reg                sdata_q
);

    localparam DIV_W = (MCLK_DIV > 1) ? $clog2(MCLK_DIV) : 1;

    reg [DIV_W-1:0] div_q;          // Position innerhalb eines MCLK-Takts
    reg [5:0]       bit_q;          // Bitplatz im Paar: 0-31 links, 32-63 rechts
    reg [15:0]      left_q;
    reg [15:0]      right_q;

    wire       mclk_start = (div_q == MCLK_DIV - 1);    // danach beginnt ein MCLK-Takt
    wire [5:0] next_bit   = bit_q + 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            div_q   <= {DIV_W{1'b0}};
            bit_q   <= 6'd63;
            mclk_q  <= 1'b0;
            sclk_q  <= 1'b0;
            lrclk_q <= 1'b1;
            sdata_q <= 1'b0;
            left_q  <= 16'd0;
            right_q <= 16'd0;
        end else begin
            div_q <= mclk_start ? {DIV_W{1'b0}} : div_q + 1'b1;

            // MCLK: 1 in der ersten Hälfte des Takts (bei ungeradem Teiler
            // ist sie einen Systemtakt kürzer als die zweite).
            if (mclk_start)                    mclk_q <= 1'b1;
            else if (div_q == MCLK_DIV / 2 - 1) mclk_q <= 1'b0;

            // SCLK wechselt mit jedem MCLK-Takt.
            if (mclk_start) begin
                sclk_q <= ~sclk_q;

                if (sclk_q) begin
                    // fallende Flanke von SCLK: nächster Bitplatz
                    bit_q   <= next_bit;
                    lrclk_q <= next_bit[5];

                    if (next_bit == 6'd0) begin
                        left_q  <= left;
                        right_q <= right;
                    end

                    // Bitplätze 1-16 jedes Kanals tragen die Daten.
                    if (next_bit[4:0] >= 5'd1 && next_bit[4:0] <= 5'd16)
                        sdata_q <= next_bit[5] ? right_q[5'd16 - next_bit[4:0]]
                                               : left_q [5'd16 - next_bit[4:0]];
                    else
                        sdata_q <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire
