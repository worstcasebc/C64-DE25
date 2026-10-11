// ascii_key_typer — "tippt" empfangene ASCII-Zeichen auf der C64-Tastatur.
//
// Zweck:  Übergangslösung, bis eine echte Tastatur angeschlossen ist: Jedes
//         Zeichen vom PC (über uart_rx) wird in die passende C64-Taste
//         übersetzt, bei Bedarf zusammen mit SHIFT. Die Taste bleibt
//         PRESS_CLKS Takte gedrückt und danach RELEASE_CLKS Takte los — das
//         KERNAL fragt die Tastatur nur rund 60-mal pro Sekunde ab und muss
//         Drücken und Loslassen jeweils sicher sehen (Default je 40 ms).
//         Übersetzung:
//           Buchstaben (groß und klein)  -> Buchstabentaste
//           Ziffern, + - * / = . , : ; @ -> gleiche Taste
//           ! " # $ % & ' ( )            -> SHIFT + 1..9
//           < > ? [ ]                    -> SHIFT + , . / : ;
//           ^                            -> Pfeil nach oben
//           Enter (CR, LF oder CR+LF)    -> RETURN (einmal)
//           Rücktaste (BS oder DEL)      -> DEL
//           Esc                          -> RUN/STOP
//         Für Tasten ohne ASCII-Zeichen gelten die Steuercodes des C64
//         (PETSCII); sw/py/c64_term.py sendet sie für die Pfeil- und
//         Funktionstasten des PCs:
//           $11 / $91  Cursor runter / hoch     $1D / $9D  rechts / links
//           $13 / $93  HOME / CLR               $14 / $94  DEL / INS
//           $85-$88    F1, F3, F5, F7           $89-$8C    F2, F4, F6, F8
//           $03        RUN/STOP
//         Alle anderen Zeichen werden ignoriert.
// Takt:   clk, synchroner Reset rst (aktiv high).
// Ports:  fifo_* — die Zeichen kommen aus einer Warteschlange (fifo_sync),
//         denn ein Terminal schickt oft eine ganze Zeile auf einmal, viel
//         schneller, als sich tippen lässt. Das Modul holt sich das nächste
//         Zeichen mit fifo_rd = 1, sobald es Zeit dafür hat; es liegt einen
//         Takt später an fifo_data an.
//         keys — gedrückte Tasten, Nummerierung siehe key_matrix.
//         busy = 1, solange getippt wird oder Zeichen warten.

`default_nettype none

module ascii_key_typer #(
    parameter PRESS_CLKS   = 2_000_000,
    parameter RELEASE_CLKS = 2_000_000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        fifo_empty,
    input  wire [7:0]  fifo_data,
    output wire        fifo_rd,
    output wire        busy,
    output wire [63:0] keys
);

    localparam [5:0] KEY_LSHIFT = 6'd15;

    // Liefert {bekannt, SHIFT, Tastennummer}.
    function [7:0] key_of(input [7:0] ascii);
        reg [7:0] ch;
        begin
            ch = (ascii >= "a" && ascii <= "z") ? ascii - 8'd32 : ascii;
            case (ch)
                "A": key_of = {2'b10, 6'd10};  "B": key_of = {2'b10, 6'd28};
                "C": key_of = {2'b10, 6'd20};  "D": key_of = {2'b10, 6'd18};
                "E": key_of = {2'b10, 6'd14};  "F": key_of = {2'b10, 6'd21};
                "G": key_of = {2'b10, 6'd26};  "H": key_of = {2'b10, 6'd29};
                "I": key_of = {2'b10, 6'd33};  "J": key_of = {2'b10, 6'd34};
                "K": key_of = {2'b10, 6'd37};  "L": key_of = {2'b10, 6'd42};
                "M": key_of = {2'b10, 6'd36};  "N": key_of = {2'b10, 6'd39};
                "O": key_of = {2'b10, 6'd38};  "P": key_of = {2'b10, 6'd41};
                "Q": key_of = {2'b10, 6'd62};  "R": key_of = {2'b10, 6'd17};
                "S": key_of = {2'b10, 6'd13};  "T": key_of = {2'b10, 6'd22};
                "U": key_of = {2'b10, 6'd30};  "V": key_of = {2'b10, 6'd31};
                "W": key_of = {2'b10, 6'd9};   "X": key_of = {2'b10, 6'd23};
                "Y": key_of = {2'b10, 6'd25};  "Z": key_of = {2'b10, 6'd12};

                "1": key_of = {2'b10, 6'd56};  "!":  key_of = {2'b11, 6'd56};
                "2": key_of = {2'b10, 6'd59};  "\"": key_of = {2'b11, 6'd59};
                "3": key_of = {2'b10, 6'd8};   "#":  key_of = {2'b11, 6'd8};
                "4": key_of = {2'b10, 6'd11};  "$":  key_of = {2'b11, 6'd11};
                "5": key_of = {2'b10, 6'd16};  "%":  key_of = {2'b11, 6'd16};
                "6": key_of = {2'b10, 6'd19};  "&":  key_of = {2'b11, 6'd19};
                "7": key_of = {2'b10, 6'd24};  "'":  key_of = {2'b11, 6'd24};
                "8": key_of = {2'b10, 6'd27};  "(":  key_of = {2'b11, 6'd27};
                "9": key_of = {2'b10, 6'd32};  ")":  key_of = {2'b11, 6'd32};
                "0": key_of = {2'b10, 6'd35};

                "+": key_of = {2'b10, 6'd40};  "-":  key_of = {2'b10, 6'd43};
                "*": key_of = {2'b10, 6'd49};  "=":  key_of = {2'b10, 6'd53};
                "@": key_of = {2'b10, 6'd46};  "^":  key_of = {2'b10, 6'd54};
                " ": key_of = {2'b10, 6'd60};
                ",": key_of = {2'b10, 6'd47};  "<":  key_of = {2'b11, 6'd47};
                ".": key_of = {2'b10, 6'd44};  ">":  key_of = {2'b11, 6'd44};
                "/": key_of = {2'b10, 6'd55};  "?":  key_of = {2'b11, 6'd55};
                ":": key_of = {2'b10, 6'd45};  "[":  key_of = {2'b11, 6'd45};
                ";": key_of = {2'b10, 6'd50};  "]":  key_of = {2'b11, 6'd50};

                8'h0D:   key_of = {2'b10, 6'd1};    // Enter -> RETURN
                8'h08:   key_of = {2'b10, 6'd0};    // Rücktaste -> DEL
                8'h7F:   key_of = {2'b10, 6'd0};
                8'h1B:   key_of = {2'b10, 6'd63};   // Esc -> RUN/STOP
                8'h03:   key_of = {2'b10, 6'd63};   // PETSCII: RUN/STOP

                8'h11:   key_of = {2'b10, 6'd7};    // Cursor runter
                8'h91:   key_of = {2'b11, 6'd7};    // Cursor hoch
                8'h1D:   key_of = {2'b10, 6'd2};    // Cursor rechts
                8'h9D:   key_of = {2'b11, 6'd2};    // Cursor links
                8'h13:   key_of = {2'b10, 6'd51};   // HOME
                8'h93:   key_of = {2'b11, 6'd51};   // CLR
                8'h14:   key_of = {2'b10, 6'd0};    // DEL
                8'h94:   key_of = {2'b11, 6'd0};    // INS
                8'h85:   key_of = {2'b10, 6'd4};    // F1
                8'h86:   key_of = {2'b10, 6'd5};    // F3
                8'h87:   key_of = {2'b10, 6'd6};    // F5
                8'h88:   key_of = {2'b10, 6'd3};    // F7
                8'h89:   key_of = {2'b11, 6'd4};    // F2
                8'h8A:   key_of = {2'b11, 6'd5};    // F4
                8'h8B:   key_of = {2'b11, 6'd6};    // F6
                8'h8C:   key_of = {2'b11, 6'd3};    // F8
                default: key_of = 8'h00;            // unbekannt
            endcase
        end
    endfunction

    localparam MAX_CLKS = (PRESS_CLKS > RELEASE_CLKS) ? PRESS_CLKS : RELEASE_CLKS;
    localparam CNT_W    = (MAX_CLKS > 1) ? $clog2(MAX_CLKS) : 1;

    localparam [1:0] S_IDLE    = 2'd0,
                     S_FETCH   = 2'd1,
                     S_PRESS   = 2'd2,
                     S_RELEASE = 2'd3;

    localparam [7:0] CR = 8'h0D, LF = 8'h0A;

    wire [7:0] decoded = key_of(fifo_data);
    wire       known   = decoded[7];

    reg [1:0]       state_q;
    reg [CNT_W-1:0] cnt_q;
    reg [6:0]       key_q;          // {SHIFT, Tastennummer} der aktuellen Taste
    reg             last_cr_q;      // das vorige Zeichen war CR

    assign fifo_rd = (state_q == S_IDLE) && !fifo_empty;
    assign busy    = (state_q != S_IDLE) || !fifo_empty;

    assign keys = (state_q != S_PRESS) ? 64'd0 :
                  (64'd1 << key_q[5:0]) | (key_q[6] ? (64'd1 << KEY_LSHIFT) : 64'd0);

    always @(posedge clk) begin
        if (rst) begin
            state_q   <= S_IDLE;
            cnt_q     <= {CNT_W{1'b0}};
            last_cr_q <= 1'b0;
        end else begin
            case (state_q)
                S_IDLE: begin
                    cnt_q <= {CNT_W{1'b0}};
                    if (!fifo_empty) state_q <= S_FETCH;
                end

                // Das geholte Zeichen liegt jetzt an fifo_data an.
                S_FETCH: begin
                    last_cr_q <= (fifo_data == CR);
                    if (fifo_data == LF) begin
                        // LF gilt als Enter, außer direkt nach CR (CR+LF).
                        key_q   <= 7'd1;
                        state_q <= last_cr_q ? S_IDLE : S_PRESS;
                    end else if (known) begin
                        key_q   <= decoded[6:0];
                        state_q <= S_PRESS;
                    end else begin
                        state_q <= S_IDLE;
                    end
                end

                S_PRESS: begin
                    if (cnt_q == PRESS_CLKS - 1) begin
                        cnt_q   <= {CNT_W{1'b0}};
                        state_q <= S_RELEASE;
                    end else begin
                        cnt_q <= cnt_q + 1'b1;
                    end
                end

                S_RELEASE: begin
                    if (cnt_q == RELEASE_CLKS - 1) state_q <= S_IDLE;
                    else                           cnt_q   <= cnt_q + 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
