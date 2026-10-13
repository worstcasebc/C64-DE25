# de25_nano_c64.sdc — Timing-Constraints
#
# Die .sdc sagt dem Timing-Analyzer, wie schnell der Takt ist. Ohne diese
# Angabe weiß Quartus nicht, wie viel Zeit ein Signal zwischen zwei Flipflops
# haben darf, und kann weder gezielt optimieren noch Verletzungen melden.

# Den 50-MHz-Takt an CLOCK0_50 und die PLL-Ausgänge legen die PLL-IPs mit
# ihrer eigenen .sdc an (u_pll_c64|iopll_0_refclk, ..._outclk0, ..._outclk1,
# u_pll_video|pll_video_outclk0, ..._outclk1); ein eigenes create_clock hier
# würde ignoriert.
# clk_sys = 31,5 MHz ist der Takt des C64, clk_vid = 74,25 MHz der Pixeltakt
# der Bildausgabe (720p50). Zwischen beiden gibt es nur zwei Wege, beide in
# video_upscaler: die Bildspeicher, in denen kein Flipflop der einen Seite
# eines der anderen speist, und den Stand des Schreibers, der durch einen
# Synchronizer läuft (nächster Absatz).
set clk_sys [get_clocks {u_pll_c64|iopll_0_outclk0}]
set clk_vid [get_clocks {u_pll_video|pll_video_outclk0}]

# Alles, was in einem Synchronizer (sync_2ff) ankommt, ist asynchron zum
# Takt, der es übernimmt: Taster, Schalter, UART-Empfang, I2C-Daten, der Interrupt des
# HDMI-Senders und das locked-Signal der PLL. Die erste Stufe braucht kein
# Timing — genau dafür ist der Synchronizer da.
set_false_path -to   [get_registers {*|meta_q[*]}]
set_false_path -from [get_ports {KEY[*] SW[*] FPGA_UART_RX HDMI_I2C_SDA HDMI_TX_INT}]

# Bytes von Linux (hps_byte_port, nur im Projekt quartus_hps): Das Byte
# wechselt mit clk_100 und wird mit clk_sys gelesen. Gelesen wird es aber
# erst, nachdem das Fähnchen durch den Synchronizer gelaufen ist — dann
# steht es seit mindestens zwei Takten still. Der Weg braucht kein Timing.
set hps_byte [get_registers -nowarn {u_hps_byte_port|data_av_q[*]}]
if {[get_collection_size $hps_byte] > 0} {
    set_false_path -from $hps_byte -to [get_registers {u_hps_byte_port|data_q[*]}]
}

# Diskette von Linux (hps_disk_port, nur im Projekt quartus_hps): Block und
# Anzahl einer Anforderung des Laufwerks wechseln mit clk_sys und werden mit
# clk_100 ins Leseregister reg_data_q übernommen. Linux wertet sie erst aus,
# wenn die Anforderung selbst durch den Synchronizer gekommen ist — dann
# stehen sie seit mindestens zwei Takten still. Der Weg braucht kein Timing.
# Der Name des Registers muss zum RTL passen: Greift die Zeile ins Leere,
# rechnet Quartus den Weg als gewöhnlichen Pfad zwischen zwei Takten und
# meldet eine Verletzung von einigen Nanosekunden.
set disk_req [get_registers -nowarn {u_hps_disk_port|reg_data_q[*]}]
if {[get_collection_size $disk_req] > 0} {
    set_false_path -from $clk_sys -to $disk_req
}

# LEDs sind fürs Auge. Der UART ist asynchron zum Empfänger (der tastet
# selbst in der Bitmitte ab); ein Bit dauert 273 Takte.
set_false_path -to [get_ports {LEDR[*] FPGA_UART_TX}]

# HDMI-Video: Die Daten wechseln mit der steigenden Flanke von clk_vid,
# der Sender ADV7513 übernimmt sie mit der steigenden Flanke von HDMI_TX_CLK.
# Er verlangt, dass die Daten 1,8 ns vor dieser Flanke stehen (Setup) und
# 1,3 ns danach noch stehen bleiben (Hold) — Datenblatt, Tabelle "AC
# Specifications". Bei 74,25 MHz (Periode 13,5 ns) ist das nicht mehr von
# selbst erfüllt, deshalb wird es hier geprüft:
#   - HDMI_TX_CLK ist für die Analyse ein eigener Takt, abgeleitet vom
#     zweiten Ausgang der PLL (derselbe Takt, in der Phase verschoben).
#   - set_output_delay beschreibt den Empfänger: -max ist seine Setup-Zeit,
#     -min seine Hold-Zeit mit umgekehrtem Vorzeichen.
# Die Verschiebung von 270 Grad (10,1 ns) steht in quartus/ip/pll_video.ip.
# Sie ist so gewählt, dass die Flanke mitten in den gültigen Bereich fällt:
# Die Daten brauchen vom Flipflop bis zum Pin länger als der Takt (bei 180
# Grad blieben nur 0,7 ns Setup-Reserve, aber 7 ns Hold-Reserve).
set hdmi_clk_src [get_clock_info -targets [get_clocks {u_pll_video|pll_video_outclk1}]]
create_generated_clock -name hdmi_tx_clk -source $hdmi_clk_src [get_ports HDMI_TX_CLK]
set_output_delay -clock hdmi_tx_clk -max  1.8 [get_ports {HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]
set_output_delay -clock hdmi_tx_clk -min -1.3 [get_ports {HDMI_TX_D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_VS}]

# I2C zum HDMI-Sender: 100 kHz, ein Viertel-Bit dauert 79 Takte.
set_false_path -to [get_ports {HDMI_I2C_SCL HDMI_I2C_SDA}]

# I2S-Ton zum HDMI-Sender: Der Empfänger übernimmt die Daten mit der
# steigenden Flanke von HDMI_SCLK, eine halbe Bitzeit (knapp 160 ns) nach dem
# Wechsel. Laufzeitunterschiede zwischen den Pins spielen dagegen keine Rolle.
set_false_path -to [get_ports {HDMI_MCLK HDMI_SCLK HDMI_LRCLK HDMI_I2S}]

# Der Design Assistant (Regel TMC-20012) verlangt für jeden Ausgang eine
# Angabe, relativ zu welchem Takt er betrachtet wird — auch wenn der Pfad
# oben vom Timing ausgenommen ist. 0 ns = "keine externe Anforderung".
set_output_delay -clock $clk_sys 0 [get_ports {LEDR[*] FPGA_UART_TX HDMI_I2C_SCL HDMI_I2C_SDA HDMI_MCLK HDMI_SCLK HDMI_LRCLK HDMI_I2S}]

# JTAG-Takt: existiert nur, wenn Signal Tap (oder anderes JTAG-Debug) im
# Design steckt. Er kommt vom USB-Blaster und hat keinen Bezug zu clk_sys,
# deshalb als eigene, asynchrone Taktgruppe.
# Nicht entfernen, auch wenn der Design Assistant im Projekt mit HPS meldet,
# die Taktgruppe decke keinen Pfad ab (TMC-20025): Ohne sie verletzen dort
# rund 60 Pfade zwischen JTAG-Takt und clk_100 das Timing (Hold und Removal,
# ausprobiert am 13.10.2026). Warum die Regel sie trotzdem als wirkungslos
# einstuft, ist ungeklaert.
if {[get_collection_size [get_ports -nowarn altera_reserved_tck]] > 0} {
    create_clock -name altera_reserved_tck -period 100.000 [get_ports altera_reserved_tck]
    set_clock_groups -asynchronous -group {altera_reserved_tck}
}