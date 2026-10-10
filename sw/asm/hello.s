; hello.s — erstes Programm für das Mini-System (Meilenstein 2).
;
; Gibt nach dem Reset eine Begrüßung aus und zählt dann sichtbar hoch:
;   6502 laeuft auf dem DE25-Nano
;   Zaehler: $00
;   Zaehler: $01
;   ...
; Benutzt dabei bewusst alle Teile des Systems: ROM (Programm und Texte),
; RAM (Zähler in der Zeropage, Stack für JSR/RTS/PHA) und das UART-Register.

UART = $DE00            ; schreiben: Byte senden; lesen: Bit 7 = Sender frei

.zeropage
counter:    .res 1

.code

reset:
        sei             ; Interrupts aus (es gibt noch keine Quellen)
        cld             ; Dezimalmodus aus
        ldx #$FF
        txs             ; Stackpointer auf $01FF
        lda #0
        sta counter

        ldx #0
@banner:
        lda banner,x
        beq main        ; 0 = Textende
        jsr putc
        inx
        bne @banner

main:
        ldx #0
@label:
        lda label,x
        beq @number
        jsr putc
        inx
        bne @label
@number:
        lda counter
        jsr puthex
        lda #$0D        ; CR
        jsr putc
        lda #$0A        ; LF
        jsr putc
        inc counter
        jsr delay
        jmp main

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
        jmp putc        ; putc kehrt für uns zurück

; delay — rund 0,33 s bei 1 MHz (256 * 256 Durchläufe zu je 5 Takten).
delay:
        ldy #0
        ldx #0
@loop:
        dex
        bne @loop
        dey
        bne @loop
        rts

irq_nmi:
        rti

.rodata
banner:     .byte "6502 laeuft auf dem DE25-Nano", $0D, $0A, 0
label:      .byte "Zaehler: $", 0
hexdigits:  .byte "0123456789ABCDEF"

.segment "VECTORS"
        .word irq_nmi   ; $FFFA NMI
        .word reset     ; $FFFC Reset
        .word irq_nmi   ; $FFFE IRQ/BRK
