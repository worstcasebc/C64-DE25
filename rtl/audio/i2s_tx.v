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
// Takt:   clk, synchroner Reset rst (aktiv high). SCLK = MCLK / 2 und
//         LRCLK = SCLK / 64 entstehen durch glattes Teilen. MCLK selbst
//         entsteht aus clk im Verhältnis MCLK_NUM / MCLK_DEN, das kein
//         glatter Teiler sein muss: Ein Zähler wächst in jedem Takt um
//         MCLK_NUM; überschreitet er MCLK_DEN, beginnt ein neuer MCLK-Takt
//         und der Überschuss bleibt stehen — wie ein Schaltjahr, das den
//         Kalender im Mittel richtig hält. Ein MCLK-Takt ist dann mal einen
//         Systemtakt kürzer, mal länger, im Mittel aber genau richtig.
//         Auf dem Board: 31,5 MHz * 512 / 2625 = 6,144 MHz, also genau
//         48000 Abtastwerte pro Sekunde (MCLK-Takte zu 5 oder 6
//         Systemtakten). Das ist nötig, weil Fernseher und Soundbars nur
//         die genormten Raten annehmen; mit dem glatten Teiler 5 waren es
//         49219 (2,5 % daneben) — ein Monitor spielte das, eine Soundbar
//         blieb stumm.
// Parameter: MCLK_NUM, MCLK_DEN — MCLK = clk * MCLK_NUM / MCLK_DEN.
//         Default 1/5: glatter Teiler 5.
// Ports:  left/right — Abtastwerte mit Vorzeichen; sie werden am Anfang
//         jedes Paars übernommen und müssen nicht synchron dazu wechseln.
//         mclk_q, sclk_q, lrclk_q, sdata_q — die vier Leitungen.

`default_nettype none

module i2s_tx #(
    parameter MCLK_NUM = 1,
    parameter MCLK_DEN = 5
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

    localparam ACC_W = $clog2(MCLK_DEN + MCLK_NUM);

    reg [ACC_W-1:0] acc_q;          // Position innerhalb eines MCLK-Takts, 0..MCLK_DEN-1
    reg [5:0]       bit_q;          // Bitplatz im Paar: 0-31 links, 32-63 rechts
    reg [15:0]      left_q;
    reg [15:0]      right_q;

    localparam [ACC_W-1:0] NUM = MCLK_NUM,
                           DEN = MCLK_DEN;

    wire [ACC_W-1:0] acc_sum    = acc_q + NUM;
    wire             mclk_start = (acc_sum >= DEN);     // danach beginnt ein MCLK-Takt
    wire [ACC_W-1:0] acc_next   = mclk_start ? acc_sum - DEN : acc_sum;
    wire [5:0] next_bit   = bit_q + 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            acc_q   <= {ACC_W{1'b0}};
            bit_q   <= 6'd63;
            mclk_q  <= 1'b0;
            sclk_q  <= 1'b0;
            lrclk_q <= 1'b1;
            sdata_q <= 1'b0;
            left_q  <= 16'd0;
            right_q <= 16'd0;
        end else begin
            acc_q <= acc_next;

            // MCLK: 1 in der ersten Hälfte des Takts (auf ganze Systemtakte
            // abgerundet).
            if (mclk_start)               mclk_q <= 1'b1;
            else if (acc_next >= DEN / 2) mclk_q <= 1'b0;

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
