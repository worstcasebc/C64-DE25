; banktest.s — Test-ROMs für die C64-Speicherkarte (Meilenstein 3).
;
; Erzeugt alle drei ROMs: BASIC und Char-ROM enthalten nur ein Kennzeichen
; am Anfang ('B' bzw. 'C'), das KERNAL-ROM enthält dieses Testprogramm.
; Es schaltet das Banking über $01 um und meldet per UART, ob an derselben
; Adresse einmal ROM und einmal RAM erscheint:
;   C64-Speicherkarte
;   BASIC-ROM  OK
;   RAM $A000  OK
;   CHAR-ROM   OK
;   RAM $D000  OK
;   RAM $E000  OK
;   CPU-PORT   OK
; Im Fehlerfall steht statt OK der gelesene Wert: FEHLER $xx.

PORT_DDR = $00          ; Richtungsregister des CPU-Ports
PORT     = $01          ; Bit 0 LORAM, Bit 1 HIRAM, Bit 2 CHAREN
UART     = $DE00        ; schreiben: Byte senden; lesen: Bit 7 = Sender frei
RAMCODE  = $0200        ; hierhin wird ramcode kopiert

.zeropage
got:        .res 1
expected:   .res 1
got_d000:   .res 1
got_e000:   .res 1

.segment "BASIC"
        .byte "B"       ; $A000

.segment "CHARROM"
        .byte "C"       ; $D000

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

irq_nmi:
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
t_fail:     .byte "FEHLER $", 0
t_ok:       .byte "OK"  ; läuft in t_eol weiter
t_eol:      .byte $0D, $0A, 0
hexdigits:  .byte "0123456789ABCDEF"

.segment "VECTORS"
        .word irq_nmi   ; $FFFA NMI
        .word reset     ; $FFFC Reset
        .word irq_nmi   ; $FFFE IRQ/BRK
