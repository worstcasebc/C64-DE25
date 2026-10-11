-- cpu_t65 — Wrapper um den 6502-Core T65 (rtl/cpu/vendor/t65).
--
-- Zweck:  T65 ist taktgenau und kennt auch die undokumentierten Befehle des
--         6510. Dieser Wrapper übersetzt seine Anschlüsse in die
--         Projektkonvention (aktiv-high, 16 Bit Adresse) und versteckt die
--         vielen Ausgänge, die hier niemand braucht. Er ist in VHDL
--         geschrieben, weil T65 einen Ausgang von einem Typ hat, den
--         Verilog nicht kennt.
--         Der I/O-Port des 6510 ($0000/$0001) steckt nicht hier, sondern in
--         rtl/cpu/cpu_port.v.
-- Takt:   clk, synchroner Reset rst (aktiv high). Die CPU macht nur in
--         Takten mit en = 1 einen Schritt.
-- Bus:    Nach einem Schritt liegen addr, dout und we für den neuen
--         CPU-Takt an und bleiben stehen. Beim nächsten Schritt übernimmt
--         die CPU die Lesedaten von din.
--         rdy = 0 lässt die CPU bei einem Lesezugriff warten; einen
--         Schreibzugriff führt sie wie der echte 6510 trotzdem aus.
--         irq und nmi sind aktiv high; der NMI wirkt auf die steigende
--         Flanke.
-- Vorlage: cpu_6510.vhd aus FPGA64 von Peter Wendrich (dort mit I/O-Port).
--          Von dort stammt auch, dass die CPU während eines Schreibzugriffs
--          ihre eigenen Schreibdaten zurückliest.

library ieee;
use ieee.std_logic_1164.all;

entity cpu_t65 is
    port (
        clk  : in  std_logic;
        rst  : in  std_logic;
        en   : in  std_logic;
        rdy  : in  std_logic;
        irq  : in  std_logic;
        nmi  : in  std_logic;
        addr : out std_logic_vector(15 downto 0);
        din  : in  std_logic_vector(7 downto 0);
        dout : out std_logic_vector(7 downto 0);
        we   : out std_logic
    );
end entity;

architecture rtl of cpu_t65 is
    signal t65_addr  : std_logic_vector(23 downto 0);
    signal t65_di    : std_logic_vector(7 downto 0);
    signal t65_do    : std_logic_vector(7 downto 0);
    signal t65_rw_n  : std_logic;   -- 1 = lesen, 0 = schreiben
    signal t65_res_n : std_logic;
    signal t65_irq_n : std_logic;
    signal t65_nmi_n : std_logic;
begin

    t65_res_n <= not rst;
    t65_irq_n <= not irq;
    t65_nmi_n <= not nmi;

    -- Beim Schreiben sieht die CPU ihre eigenen Daten.
    t65_di <= din when t65_rw_n = '1' else t65_do;

    u_t65 : entity work.T65
        port map (
            Mode    => "00",        -- 6502
            Res_n   => t65_res_n,
            Enable  => en,
            Clk     => clk,
            Rdy     => rdy,
            Abort_n => '1',
            IRQ_n   => t65_irq_n,
            NMI_n   => t65_nmi_n,
            SO_n    => '1',
            R_W_n   => t65_rw_n,
            A       => t65_addr,
            DI      => t65_di,
            DO      => t65_do
        );

    addr <= t65_addr(15 downto 0);
    dout <= t65_do;
    we   <= not t65_rw_n;

end architecture;
