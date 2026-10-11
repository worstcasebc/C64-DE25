// key_matrix — Tastaturgitter des C64 (8 x 8 Tasten).
//
// Zweck:  Im C64 liegen die Tasten an den Kreuzungen von 8 Leitungen an
//         Port A und 8 Leitungen an Port B der CIA 1. Eine gedrückte Taste
//         verbindet "ihre" beiden Leitungen. Das KERNAL legt über Port A
//         eine Leitung auf 0 und liest an Port B, wo die 0 wieder
//         herauskommt — so findet es die Taste.
//         Taste Nummer n sitzt an Port-A-Leitung n / 8 und Port-B-Leitung
//         n % 8:
//                PB0   PB1   PB2   PB3   PB4   PB5   PB6   PB7
//           PA0  DEL   RET   CRSR> F7    F1    F3    F5    CRSRv
//           PA1  3     W     A     4     Z     S     E     LSHIFT
//           PA2  5     R     D     6     C     F     T     X
//           PA3  7     Y     G     8     B     H     U     V
//           PA4  9     I     J     0     M     K     O     N
//           PA5  +     P     L     -     .     :     @     ,
//           PA6  Pfund *     ;     HOME  RSHIFT =    ^     /
//           PA7  1     <-    CTRL  2     SPACE C=    Q     STOP
// Takt:   keiner (rein kombinatorisch).
// Ports:  keys[n] = 1: Taste n ist gedrückt. pa — Pegel, die die CIA an
//         Port A ausgibt. pb — Pegel für Port B: 0, wenn in dieser Spalte
//         eine gedrückte Taste an einer auf 0 gelegten Port-A-Leitung hängt.
// Vereinfachung: nur die Richtung Port A -> Port B; keine Joysticks.

`default_nettype none

module key_matrix (
    input  wire [63:0] keys,
    input  wire [7:0]  pa,
    output wire [7:0]  pb
);

    genvar a, b;
    generate
        for (b = 0; b < 8; b = b + 1) begin : g_pb
            wire [7:0] pulled;
            for (a = 0; a < 8; a = a + 1) begin : g_pa
                assign pulled[a] = keys[a * 8 + b] & ~pa[a];
            end
            assign pb[b] = ~|pulled;
        end
    endgenerate

endmodule

`default_nettype wire
