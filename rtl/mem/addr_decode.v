// addr_decode — Address-Decoder des Mini-Systems (Meilenstein 2).
//
// Zweck:  Entscheidet anhand der Adresse, welcher Baustein gemeint ist.
//         Die Aufteilung folgt schon dem C64, damit Meilenstein 3 sie nur
//         erweitern muss:
//           $0000-$7FFF  RAM (32 KB)
//           $DE00-$DEFF  UART (im C64: freier I/O-Bereich 1)
//           $E000-$FFFF  ROM (im C64: KERNAL, enthält die Reset-Vektoren)
//           alles andere unbelegt
// Takt:   keiner (rein kombinatorisch).
// Ports:  addr -> genau eines oder keines der sel_*-Signale ist 1.

`default_nettype none

module addr_decode (
    input  wire [15:0] addr,
    output wire        sel_ram,
    output wire        sel_uart,
    output wire        sel_rom
);

    assign sel_ram  = (addr[15]    == 1'b0);
    assign sel_uart = (addr[15:8]  == 8'hDE);
    assign sel_rom  = (addr[15:13] == 3'b111);

endmodule

`default_nettype wire
