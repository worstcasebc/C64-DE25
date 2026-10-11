# de25_nano_c64.sdc — Timing-Constraints
#
# Die .sdc sagt dem Timing-Analyzer, wie schnell der Takt ist. Ohne diese
# Angabe weiß Quartus nicht, wie viel Zeit ein Signal zwischen zwei Flipflops
# haben darf, und kann weder gezielt optimieren noch Verletzungen melden.

# Den 50-MHz-Takt an CLOCK0_50 und die beiden PLL-Ausgänge legt die PLL-IP
# mit ihrer eigenen .sdc an (u_pll_c64|iopll_0_refclk, ..._outclk0,
# ..._outclk1); ein eigenes create_clock hier würde ignoriert.
# clk_sys = outclk0 = 31,5 MHz ist der Takt des ganzen Designs.
set clk_sys [get_clocks {u_pll_c64|iopll_0_outclk0}]

# Alles, was in einem Synchronizer (sync_2ff) ankommt, ist asynchron zu
# clk_sys: Taster, Schalter, UART-Empfang, I2C-Daten, der Interrupt des
# HDMI-Senders und das locked-Signal der PLL. Die erste Stufe braucht kein
# Timing — genau dafür ist der Synchronizer da.
set_false_path -to   [get_registers {*|meta_q[*]}]
set_false_path -from [get_ports {KEY[*] SW[*] FPGA_UART_RX HDMI_I2C_SDA HDMI_TX_INT}]

# LEDs sind fürs Auge. Der UART ist asynchron zum Empfänger (der tastet
# selbst in der Bitmitte ab); ein Bit dauert 273 Takte.
set_false_path -to [get_ports {LEDR[*] FPGA_UART_TX}]

# HDMI-Video: Die Daten wechseln mit der steigenden Flanke von clk_sys,
# HDMI_TX_CLK ist derselbe Takt um 180 Grad verschoben. Der Sender übernimmt
# die Daten also eine halbe Periode (knapp 16 ns) nach dem Wechsel. Gegen
# diese Reserve sind die Laufzeitunterschiede zwischen den Pins klein;
# deshalb hier keine genaue Prüfung.
set_false_path -to [get_ports {HDMI_TX_CLK HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]

# I2C zum HDMI-Sender: 100 kHz, ein Viertel-Bit dauert 79 Takte.
set_false_path -to [get_ports {HDMI_I2C_SCL HDMI_I2C_SDA}]

# I2S-Ton zum HDMI-Sender: Der Empfänger übernimmt die Daten mit der
# steigenden Flanke von HDMI_SCLK, eine halbe Bitzeit (knapp 160 ns) nach dem
# Wechsel. Laufzeitunterschiede zwischen den Pins spielen dagegen keine Rolle.
set_false_path -to [get_ports {HDMI_MCLK HDMI_SCLK HDMI_LRCLK HDMI_I2S}]

# Der Design Assistant (Regel TMC-20012) verlangt für jeden Ausgang eine
# Angabe, relativ zu welchem Takt er betrachtet wird — auch wenn der Pfad
# oben vom Timing ausgenommen ist. 0 ns = "keine externe Anforderung".
set_output_delay -clock $clk_sys 0 [get_ports {LEDR[*] FPGA_UART_TX HDMI_TX_CLK HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS HDMI_I2C_SCL HDMI_I2C_SDA HDMI_MCLK HDMI_SCLK HDMI_LRCLK HDMI_I2S}]

# JTAG-Takt: existiert nur, wenn Signal Tap (oder anderes JTAG-Debug) im
# Design steckt. Er kommt vom USB-Blaster und hat keinen Bezug zu clk_sys,
# deshalb als eigene, asynchrone Taktgruppe.
if {[get_collection_size [get_ports -nowarn altera_reserved_tck]] > 0} {
    create_clock -name altera_reserved_tck -period 100.000 [get_ports altera_reserved_tck]
    set_clock_groups -asynchronous -group {altera_reserved_tck}
}