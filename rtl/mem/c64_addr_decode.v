// c64_addr_decode — Address-Decoder des C64 mit Banking (Meilenstein 3).
//
// Zweck:  Übernimmt die Aufgabe der PLA im C64: Aus Adresse und den drei
//         Banking-Leitungen des CPU-Ports (cpu_port) wird bestimmt, wer beim
//         LESEN antwortet. Ohne Steckmodul (GAME = EXROM = 1) gilt:
//           $0000-$0001  CPU-Port                      immer
//           $A000-$BFFF  BASIC-ROM   wenn LORAM und HIRAM
//           $D000-$DFFF  I/O         wenn (LORAM oder HIRAM) und CHAREN
//                        Char-ROM    wenn (LORAM oder HIRAM) und nicht CHAREN
//           $E000-$FFFF  KERNAL-ROM  wenn HIRAM
//           alles andere, und alles Ausgeblendete: RAM
// Takt:   keiner (rein kombinatorisch).
// Ports:  Genau eines der sel_*-Signale ist 1.
// Schreiben: ROMs kann man nicht beschreiben — ein Schreibzugriff auf einen
//         ROM-Bereich landet im RAM dahinter. Die Umgebung schreibt deshalb
//         ins RAM, sobald weder sel_port noch sel_io aktiv ist.

`default_nettype none

module c64_addr_decode (
    input  wire [15:0] addr,
    input  wire        loram,
    input  wire        hiram,
    input  wire        charen,
    output wire        sel_port,
    output wire        sel_ram,
    output wire        sel_basic,
    output wire        sel_char,
    output wire        sel_io,
    output wire        sel_kernal
);

    wire in_a000 = (addr[15:13] == 3'b101);    // $A000-$BFFF
    wire in_d000 = (addr[15:12] == 4'hD);      // $D000-$DFFF
    wire in_e000 = (addr[15:13] == 3'b111);    // $E000-$FFFF

    assign sel_port   = (addr[15:1] == 15'd0);
    assign sel_basic  = in_a000 & loram & hiram;
    assign sel_io     = in_d000 & (loram | hiram) &  charen;
    assign sel_char   = in_d000 & (loram | hiram) & ~charen;
    assign sel_kernal = in_e000 & hiram;
    assign sel_ram    = ~(sel_port | sel_basic | sel_io | sel_char | sel_kernal);

endmodule

`default_nettype wire
