# pal_test.sdc — Timing-Constraints für die Revision pal_test

# Den 50-MHz-Takt an CLOCK0_50 und die beiden PLL-Ausgänge legt die PLL-IP
# mit ihrer eigenen .sdc an (u_pll_c64|iopll_0_refclk, ..._outclk0,
# ..._outclk1); ein eigenes create_clock hier würde ignoriert.
set clk_sys [get_clocks {u_pll_c64|iopll_0_outclk0}]

# Taster/Schalter sind asynchron und laufen über sync_2ff; LEDs sind fürs Auge.
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDR[*]}]

# Alles, was in u_sync_in ankommt, ist asynchron zu clk_sys — auch das
# locked-Signal der PLL, das Quartus sonst als normalen Pfad prüft. Der
# Synchronizer ist genau dafür da; die erste Stufe braucht kein Timing.
set_false_path -to [get_registers {u_sync_in|meta_q[*]}]

# HDMI-Video: Die Daten wechseln mit der steigenden Flanke des PLL-Takts,
# HDMI_TX_CLK ist derselbe Takt um 180 Grad verschoben. Der Sender übernimmt
# die Daten also eine halbe Periode (knapp 16 ns) nach dem Wechsel. Gegen
# diese Reserve sind die Laufzeitunterschiede zwischen den Pins klein;
# deshalb hier keine genaue Prüfung.
set_false_path -to [get_ports {HDMI_TX_CLK HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]

# I2C zum HDMI-Sender: 100 kHz, Eingänge asynchron über sync_2ff.
set_false_path -to   [get_ports {HDMI_I2C_SCL HDMI_I2C_SDA}]
set_false_path -from [get_ports {HDMI_I2C_SDA HDMI_TX_INT}]

# Der Design Assistant (Regel TMC-20012) verlangt für jeden Ausgang eine
# Angabe, relativ zu welchem Takt er betrachtet wird — auch wenn der Pfad
# oben vom Timing ausgenommen ist. 0 ns = "keine externe Anforderung".
set_output_delay -clock $clk_sys 0 [get_ports {LEDR[*] HDMI_TX_CLK HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS HDMI_I2C_SCL HDMI_I2C_SDA}]