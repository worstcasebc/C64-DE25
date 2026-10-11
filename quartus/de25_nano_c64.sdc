# de25_nano_c64.sdc — Timing-Constraints
#
# Die .sdc sagt dem Timing-Analyzer, wie schnell der Takt ist. Ohne diese
# Angabe weiß Quartus nicht, wie viel Zeit ein Signal zwischen zwei Flipflops
# haben darf, und kann weder gezielt optimieren noch Verletzungen melden.

# 50-MHz-Boardtakt (Periode 20 ns)
create_clock -name clk_50 -period 20.000 [get_ports CLOCK0_50]

# Taster/Schalter sind asynchron (kein Bezug zu clk_50) und laufen über
# sync_2ff; LEDs sind fürs Auge. Hier gibt es kein sinnvolles Timing zu prüfen.
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDR[*]}]

# Der Design Assistant (Regel TMC-20012) verlangt für jeden Ausgang eine
# Angabe, relativ zu welchem Takt er betrachtet wird — auch wenn der Pfad
# oben vom Timing ausgenommen ist. 0 ns = "keine externe Anforderung".
set_output_delay -clock clk_50 0 [get_ports {LEDR[*]}]

# UART ist asynchron zum Empfänger (der tastet selbst in der Bitmitte ab);
# ein Bit dauert 434 Takte, Nanosekunden am Pin spielen keine Rolle.
set_false_path   -to [get_ports FPGA_UART_TX]
set_output_delay -clock clk_50 0 [get_ports FPGA_UART_TX]

# Der Empfang ist ebenfalls asynchron und läuft über sync_2ff.
set_false_path -from [get_ports FPGA_UART_RX]

# HDMI-Video: Daten und Takt kommen aus derselben Domäne. Die Daten wechseln
# mit der fallenden Flanke von HDMI_TX_CLK, der Sender übernimmt sie mit der
# steigenden — also 20 ns nach dem Wechsel und 20 ns vor dem nächsten. Gegen
# diese Reserve sind die Laufzeitunterschiede zwischen den Pins (wenige ns)
# klein; deshalb hier keine genaue Prüfung.
set_false_path   -to [get_ports {HDMI_TX_CLK HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]
set_output_delay -clock clk_50 0 [get_ports {HDMI_TX_CLK HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]

# I2C zum HDMI-Sender: 100 kHz, ein Viertel-Bit dauert 125 Takte. Die
# Eingänge sind asynchron und laufen über sync_2ff.
set_false_path   -to   [get_ports {HDMI_I2C_SCL HDMI_I2C_SDA}]
set_false_path   -from [get_ports {HDMI_I2C_SDA HDMI_TX_INT}]
set_output_delay -clock clk_50 0 [get_ports {HDMI_I2C_SCL HDMI_I2C_SDA}]

# JTAG-Takt: existiert nur, wenn Signal Tap (oder anderes JTAG-Debug) im
# Design steckt. Er kommt vom USB-Blaster und hat keinen Bezug zu clk_50,
# deshalb als eigene, asynchrone Taktgruppe.
if {[get_collection_size [get_ports -nowarn altera_reserved_tck]] > 0} {
    create_clock -name altera_reserved_tck -period 100.000 [get_ports altera_reserved_tck]
    set_clock_groups -asynchronous -group {altera_reserved_tck}
}
