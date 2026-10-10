// cpu_6502 — Wrapper um Arlet Ottens' 6502-Core (rtl/cpu/vendor/arlet_6502).
//
// Zweck:  Übersetzt die Portnamen des Fremd-Cores in die Projektkonvention
//         und macht aus dessen RDY-Eingang eine Taktfreigabe: Die CPU macht
//         nur in Takten mit en = 1 einen Schritt.
// Takt:   clk, synchroner Reset rst (aktiv high).
// Bus:    Der Core erwartet synchronen Speicher: addr/dout/we gelten für den
//         aktuellen Schritt, din muss beim NÄCHSTEN Schritt die gelesenen
//         Daten liefern.
//         Wichtig: Zwischen zwei Schritten (en = 0) sind addr/dout/we nicht
//         verlässlich. Speicher und I/O dürfen sie deshalb nur in Takten mit
//         en = 1 übernehmen und müssen din bis zum nächsten Schritt halten.

`default_nettype none

module cpu_6502 (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    output wire [15:0] addr,
    input  wire [7:0]  din,
    output wire [7:0]  dout,
    output wire        we,
    input  wire        irq,
    input  wire        nmi
);

    cpu u_cpu (
        .clk   (clk),
        .reset (rst),
        .AB    (addr),
        .DI    (din),
        .DO    (dout),
        .WE    (we),
        .IRQ   (irq),
        .NMI   (nmi),
        .RDY   (en)
    );

endmodule

`default_nettype wire
