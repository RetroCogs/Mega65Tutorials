// ------------------------------------------------------------
//
// Tutorial 0 - Blank.
//
.cpu _45gs02				

// ------------------------------------------------------------
//
.macro BasicUpstart65(addr) {
* = $2001 "BasicUpstart65"

	.var addrStr = toIntString(addr)

	.byte $09,$20 //End of command marker (first byte after the 00 terminator)
	.byte $0a,$00 //10
	.byte $fe,$02,$30,$00 //BANK 0
	.byte <end, >end //End of command marker (first byte after the 00 terminator)
	.byte $14,$00 //20
	.byte $9e //SYS
	.text addrStr
	.byte $00
end:
	.byte $00,$00	//End of basic terminators
}

// ------------------------------------------------------------
//
BasicUpstart65(Entry)
* = $2016 "Basic Entry"

Entry: {

    ldx #$00
!:
    txa
    lsr
    lsr
    lsr
    lsr
    tay
    lda hextable,y
    sta $0800
    txa
    and #$0f
    tay
    lda hextable,y
    sta $0801
    
    cpx #$2f                            // skip knock-register $d02f
    beq skipbadregs
    cpx #$73                            // skip RASTERHEIGHT/ALPHADELAY
    beq skipbadregs
    cpx #$54                            // skip $d054 for now and handle later to exclude PALEMU bit
    beq skipbadregs
    cpx #$30                            // skip rom states
    beq skipbadregs
    cpx #$67                            // skip (undocumented) SBPDEBUG
    beq skipbadregs
    lda d000table,x
    sta $d000,x
skipbadregs:

// keyloop:
// 	lda $d610
// 	beq keyloop
// 	sta $d610

    inx
    cpx #$90
    bne !-

    rts

}

hextable:
        .text "0123456789abcdef"

d000table:
        .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00    // 00
        .byte $00, $1B, $00, $00, $00, $00, $C9, $00, $24, $70, $F1, $00, $00, $00, $00, $00    // 10
        .byte $06, $06, $01, $02, $03, $01, $02, $01, $01, $02, $03, $04, $05, $06, $07, $53    // 20
        .byte $64, $E0, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00    // 30
        .byte $01, $78, $01, $78, $01, $78, $01, $78, $68, $00, $F8, $01, $4F, $00, $68, $00    // 40
        .byte $00, $81, $00, $00, $60, $00, $00, $00, $50, $00, $78, $01, $50, $C0, $50, $00    // 50
        .byte $00, $08, $00, $00, $00, $00, $00, $00, $00, $10, $00, $00, $F8, $0F, $00, $00    // 60
        .byte $FF, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $18, $d2, $FF, $FF, $7F    // 70
        .byte $08, $00, $00, $2A, $27, $02, $00, $4C, $FF, $60, $00, $FF, $FF, $FF, $FF, $00    // 80
