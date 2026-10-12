; banktest.s — Test-ROMs für die C64-Speicherkarte (Meilenstein 3).
;
; Erzeugt alle drei ROMs: Das BASIC-ROM enthält nur das Kennzeichen 'B' am
; Anfang. Das Char-ROM beginnt mit dem Kennzeichen 'C'; danach besteht jedes
; Zeichen aus acht gleichen Zeilen mit dem eigenen Zeichencode als Muster —
; auf dem Bildschirm zeigt jedes Zeichen so seinen Code als Streifen, und
; die Testbench kann jedes Pixel nachrechnen. Das KERNAL-ROM enthält dieses
; Testprogramm.
; Es schaltet das Banking über $01 um und meldet per UART, ob an derselben
; Adresse einmal ROM und einmal RAM erscheint:
;   C64-Speicherkarte
;   BASIC-ROM  OK
;   RAM $A000  OK
;   CHAR-ROM   OK
;   RAM $D000  OK
;   RAM $E000  OK
;   CPU-PORT   OK
;   CIA-IRQ    OK
;   CIA-NMI    OK
;   IEC-BUS    OK
; Im Fehlerfall steht statt OK der gelesene Wert: FEHLER $xx.
; IEC-BUS braucht ein Laufwerk am seriellen Bus (oder die Testbench, die eines
; spielt); ohne meldet die Zeile FEHLER $E7.
; Zum Schluss füllt es den Bildschirmspeicher: Titel in Zeile 0, ab Zeile 2
; alle 256 Zeichen in der Reihenfolge ihrer Codes, sonst Leerzeichen.
; Farben wie beim C64-Start (Rahmen und Schrift hellblau, Hintergrund blau),
; nur der Titel ist weiß.

PORT_DDR = $00          ; Richtungsregister des CPU-Ports
PORT     = $01          ; Bit 0 LORAM, Bit 1 HIRAM, Bit 2 CHAREN
UART     = $DE00        ; schreiben: Byte senden; lesen: Bit 7 = Sender frei
RAMCODE  = $0200        ; hierhin wird ramcode kopiert
SCREEN   = $0400        ; Bildschirmspeicher, 40 x 25 Zeichen
COLORS   = $D800        ; Farb-RAM, eine Farbe (0-15) pro Zeichen
SID_VOL  = $D418        ; SID: Lautstärke (untere 4 Bit) und Filterart
VIC_CR1  = $D011        ; VIC: Bit 4 Bildschirm an, Bit 3 25 Zeilen, Bit 0-2 Feinverschiebung
VIC_CR2  = $D016        ; VIC: Bit 3 40 Spalten
VIC_MEM  = $D018        ; VIC: wo Bildschirmspeicher und Zeichensatz liegen
BORDER   = $D020        ; VIC: Rahmenfarbe
BGCOLOR  = $D021        ; VIC: Hintergrundfarbe
CIA_TALO = $DC04        ; CIA 1: Timer A, unteres Byte
CIA_TAHI = $DC05        ; CIA 1: Timer A, oberes Byte
CIA_ICR  = $DC0D        ; CIA 1: Interrupts melden/freigeben
CIA_CRA  = $DC0E        ; CIA 1: Timer A steuern
CIA2_PA   = $DD00       ; CIA 2: Port A, Bit 3-7 sind der serielle Bus
CIA2_DDRA = $DD02       ; CIA 2: Richtung von Port A (1 = Ausgang)
CIA2_TBLO = $DD06       ; CIA 2: Timer B, unteres Byte
CIA2_TBHI = $DD07       ; CIA 2: Timer B, oberes Byte
CIA2_ICR  = $DD0D       ; CIA 2: ihre Interrupts gehen an den NMI
CIA2_CRB  = $DD0F       ; CIA 2: Timer B steuern

.zeropage
got:        .res 1
expected:   .res 1
got_d000:   .res 1
got_e000:   .res 1
irq_count:  .res 1
nmi_count:  .res 1

.segment "BASIC"
        .byte "B"       ; $A000

.segment "CHARROM"
        .byte "C", 0, 0, 0, 0, 0, 0, 0  ; $D000: Zeichen 0
        .repeat 255, i                  ; Zeichen 1..255
            .repeat 8
                .byte i + 1
            .endrepeat
        .endrepeat

.code

reset:
        sei             ; Interrupts aus (es gibt noch keine Quellen)
        cld             ; Dezimalmodus aus
        ldx #$FF
        txs             ; Stackpointer auf $01FF
        lda #$37        ; erst der Wert, dann die Richtung: so wechseln die
        sta PORT        ; Leitungen ohne Sprung von "Pull-up 1" auf "Ausgang 1"
        lda #$2F
        sta PORT_DDR

        ldx #(t_title - text)
        jsr puts

        ; BASIC-ROM ist sichtbar. Schreiben landet im RAM dahinter, gelesen
        ; wird weiterhin das ROM.
        lda #$55
        sta $A000
        lda $A000
        ldy #'B'
        ldx #(t_basic - text)
        jsr report

        ; LORAM = 0: BASIC weg, das eben geschriebene RAM kommt zum Vorschein.
        lda #$36
        sta PORT
        lda $A000
        pha
        lda #$37
        sta PORT
        pla
        ldy #$55
        ldx #(t_ram_a - text)
        jsr report

        ; CHAREN = 0: Char-ROM statt I/O. Der UART ist solange unsichtbar,
        ; deshalb erst zurückschalten, dann melden.
        lda #$33
        sta PORT
        lda $D000
        pha
        lda #$37
        sta PORT
        pla
        ldy #'C'
        ldx #(t_char - text)
        jsr report

        ; RAM unter I/O und KERNAL. Dafür muss der KERNAL ausgeblendet werden
        ; — also auch dieses Programm. Deshalb läuft der Teil aus dem RAM.
        lda #$AA
        sta $E000       ; landet im RAM unter dem KERNAL
        ldx #(ramcode_end - ramcode - 1)
@copy:
        lda ramcode,x
        sta RAMCODE,x
        dex
        bpl @copy
        jsr RAMCODE

        lda got_d000
        ldy #$66
        ldx #(t_ram_d - text)
        jsr report

        lda got_e000
        ldy #$AA
        ldx #(t_ram_e - text)
        jsr report

        ; Lesen von $01 liefert den Pegel der Leitungen.
        lda PORT
        ldy #$37
        ldx #(t_port - text)
        jsr report

        ; Timer-Interrupt: Timer A läuft alle 101 Schritte ab und löst einen
        ; IRQ aus; die Routine irq zählt mit. Drei Interrupts müssen kommen.
        lda #0
        sta irq_count
        lda #100
        sta CIA_TALO
        lda #0
        sta CIA_TAHI
        lda #$81        ; Unterlauf von Timer A darf IRQ auslösen
        sta CIA_ICR
        lda #$11        ; Startwert laden und fortlaufend starten
        sta CIA_CRA
        cli             ; Interrupts zulassen
        ldx #0
        ldy #0
@wait:
        lda irq_count
        cmp #3
        bcs @enough
        dex
        bne @wait
        dey
        bne @wait       ; nach 65536 Runden aufgeben
@enough:
        sei
        lda #$7F        ; alle Interrupts der CIA sperren
        sta CIA_ICR
        lda #0          ; Timer anhalten
        sta CIA_CRA
        lda irq_count
        cmp #3
        bcc @counted    ; weniger als 3: so melden
        lda #3          ; 3 oder mehr gilt als bestanden
@counted:
        ldy #3
        ldx #(t_irq - text)
        jsr report

        ; NMI: Timer B der zweiten CIA läuft alle 101 Schritte ab. Der NMI
        ; lässt sich nicht sperren (sei wirkt nicht); die Routine nmi zählt
        ; mit. Drei müssen kommen.
        lda #0
        sta nmi_count
        lda #100
        sta CIA2_TBLO
        lda #0
        sta CIA2_TBHI
        lda #$82        ; Unterlauf von Timer B darf den Interrupt auslösen
        sta CIA2_ICR
        lda #$11        ; Startwert laden und fortlaufend starten
        sta CIA2_CRB
        ldx #0
        ldy #0
@wait_nmi:
        lda nmi_count
        cmp #3
        bcs @enough_nmi
        dex
        bne @wait_nmi
        dey
        bne @wait_nmi   ; nach 65536 Runden aufgeben
@enough_nmi:
        lda #$7F        ; alle Interrupts der zweiten CIA sperren
        sta CIA2_ICR
        lda #0          ; Timer anhalten
        sta CIA2_CRB
        lda nmi_count
        cmp #3
        bcc @counted_nmi
        lda #3
@counted_nmi:
        ldy #3
        ldx #(t_nmi - text)
        jsr report

        ; Serieller Bus: Bit 3 (ATN), 4 (CLK) und 5 (DATA) von Port A ziehen
        ; mit einer 1 die jeweilige Leitung auf 0; an Bit 6 (CLK) und 7
        ; (DATA) liest man den Pegel der Leitung. Vier Schritte, je zwei
        ; gelesene Bits, zusammen ein Byte:
        ;   nichts ziehen   DATA 1, CLK 1
        ;   CLK ziehen      DATA 1, CLK 0
        ;   DATA ziehen     DATA 0, CLK 1
        ;   ATN ziehen      DATA 0, CLK 1   (das Laufwerk antwortet mit DATA)
        ; Bit 0 und 1 bleiben 1, damit der VIC-II seine Speicherbank behält.
        lda #$3F
        sta CIA2_DDRA
        lda #0
        sta got
        ldx #0
@iec:
        lda iec_out,x
        sta CIA2_PA
        nop             ; der Pegel wird einmal pro Takt übernommen
        lda CIA2_PA
        asl a           ; Bit 7 (DATA) ins Carry ...
        rol got         ; ... und von rechts in got schieben
        asl a           ; Bit 6 (CLK)
        rol got
        inx
        cpx #4
        bne @iec
        lda #$07        ; alle Leitungen wieder loslassen
        sta CIA2_PA
        lda got
        ldy #$E5        ; %11 10 01 01
        ldx #(t_iec - text)
        jsr report

        ; SID: volle Lautstärke, wie es das KERNAL beim Start einstellt. Das
        ; Register lässt sich nicht zurücklesen; die Testbench schaut nach,
        ; ob der Wert beim SID angekommen ist.
        lda #$0F
        sta SID_VOL

        ; VIC-II einstellen wie das KERNAL: Textbildschirm an, 25 Zeilen,
        ; 40 Spalten, Bildschirmspeicher $0400, Zeichensatz $1000 (Char-ROM).
        lda #$1B
        sta VIC_CR1
        lda #$C8
        sta VIC_CR2
        lda #$14
        sta VIC_MEM

        ; Farben: Rahmen hellblau (14), Hintergrund blau (6).
        lda #14
        sta BORDER
        lda #6
        sta BGCOLOR

        ; Bildschirm löschen: 1000 Zeichen in vier Stücken zu je 256 (das
        ; letzte überlappt). Leerzeichen hat den Bildschirmcode $20.
        ldx #0
        lda #$20
@clear:
        sta SCREEN,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + $2E8,x
        inx
        bne @clear

        ; Farb-RAM genauso füllen: alle Zeichen hellblau.
        lda #14
@colors:
        sta COLORS,x
        sta COLORS + $100,x
        sta COLORS + $200,x
        sta COLORS + $2E8,x
        inx
        bne @colors

        ; Titel in Zeile 0. Bildschirmcodes sind kein ASCII: A-Z haben die
        ; Codes 1-26; Ziffern und Satzzeichen bleiben gleich. "and #$3F"
        ; macht aus ASCII-Großbuchstaben den Bildschirmcode.
        ldx #0
@title:
        lda t_screen,x
        beq @charset
        and #$3F
        sta SCREEN,x
        lda #1          ; Titel in Weiß
        sta COLORS,x
        inx
        bne @title

        ; Alle 256 Zeichen ab Zeile 2.
@charset:
        ldx #0
@codes:
        txa
        sta SCREEN + 80,x
        inx
        bne @codes

done:
        jmp done

; ramcode — wird nach RAMCODE kopiert und dort ausgeführt. Enthält keine
; Sprünge und keine absoluten Adressen in sich selbst, läuft also überall.
ramcode:
        lda #$34        ; LORAM = HIRAM = 0: überall RAM
        sta PORT
        lda #$66
        sta $D000       ; jetzt RAM, nicht mehr I/O
        lda $D000
        sta got_d000
        lda $E000
        sta got_e000
        lda #$37        ; ROMs und I/O wieder einblenden
        sta PORT
        rts
ramcode_end:

; report — gibt den Text ab text+X aus, dann OK, wenn A = Y ist, sonst
; FEHLER und den Wert aus A.
report:
        sta got
        sty expected
        jsr puts
        lda got
        cmp expected
        bne @fail
        ldx #(t_ok - text)
        jmp puts        ; puts kehrt für uns zurück
@fail:
        ldx #(t_fail - text)
        jsr puts
        lda got
        jsr puthex
        ldx #(t_eol - text)
        jmp puts

; puts — gibt den Text ab text+X bis zum 0-Byte aus. Verändert A und X.
puts:
        lda text,x
        beq @done
        jsr putc
        inx
        bne puts
@done:
        rts

; putc — sendet das Zeichen in A. Wartet, bis der Sender frei ist.
putc:
        bit UART        ; kopiert Bit 7 von UART ins N-Flag
        bpl putc        ; N = 0 -> noch beschäftigt
        sta UART
        rts

; puthex — gibt A als zwei Hex-Ziffern aus. Verändert A und Y.
puthex:
        pha
        lsr a
        lsr a
        lsr a
        lsr a           ; oberes Halbbyte nach unten
        tay
        lda hexdigits,y
        jsr putc
        pla
        and #$0F        ; unteres Halbbyte
        tay
        lda hexdigits,y
        jmp putc

; irq — Interrupt der CIA: quittieren (Lesen von ICR löscht die Meldung,
; sonst käme der IRQ sofort wieder) und mitzählen.
irq:
        pha
        lda CIA_ICR
        inc irq_count
        pla
        rti

; nmi — Interrupt der zweiten CIA: quittieren und mitzählen. Der NMI
; reagiert nur auf den Wechsel der Leitung; ohne das Lesen von ICR bliebe
; sie stehen, und es käme kein weiterer.
nmi:
        pha
        lda CIA2_ICR
        inc nmi_count
        pla
        rti

.rodata
; Alle Texte zusammen müssen unter 256 Bytes bleiben (Index in X).
text:
t_title:    .byte "C64-Speicherkarte", $0D, $0A, 0
t_basic:    .byte "BASIC-ROM  ", 0
t_ram_a:    .byte "RAM $A000  ", 0
t_char:     .byte "CHAR-ROM   ", 0
t_ram_d:    .byte "RAM $D000  ", 0
t_ram_e:    .byte "RAM $E000  ", 0
t_port:     .byte "CPU-PORT   ", 0
t_irq:      .byte "CIA-IRQ    ", 0
t_nmi:      .byte "CIA-NMI    ", 0
t_iec:      .byte "IEC-BUS    ", 0
t_fail:     .byte "FEHLER $", 0
t_ok:       .byte "OK"  ; läuft in t_eol weiter
t_eol:      .byte $0D, $0A, 0
hexdigits:  .byte "0123456789ABCDEF"
t_screen:   .byte "DE25-NANO C64 TEXTMODUS", 0
; Port A der CIA 2 für die vier Schritte des Bus-Tests
iec_out:    .byte $07, $17, $27, $0F

.segment "VECTORS"
        .word nmi       ; $FFFA NMI
        .word reset     ; $FFFC Reset
        .word irq       ; $FFFE IRQ/BRK
