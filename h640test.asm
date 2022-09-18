.cpu _45gs02				
#import "includes/m65macros.s"

// ------------------------------------------------------------
//
.const COLOR_RAM = $ff80000

.const SCREEN_WIDTH = 40
.const SCREEN_HEIGHT = 25
.const NUM_SCREENS_WIDE = 2
.const NUM_SCREENS_HIGH = 2

.const LOGICAL_ROW_SIZE = SCREEN_WIDTH * NUM_SCREENS_WIDE
.const LOGICAL_NUM_ROWS = SCREEN_HEIGHT * NUM_SCREENS_HIGH

// ------------------------------------------------------------
//
* = $02 "Basepage" virtual
	ChrPtr:			.word $0000
	ColPtr:			.dword $00000000

	XPos:			.word $0000
	YPos:			.word $0000

	FrameCount:		.byte $00

	XCourse:		.word $0000
	YCourse:		.word $0000

// ------------------------------------------------------------
//
BasicUpstart65(Entry)
* = $2016 "Basic Entry"

Entry: {
	sei 
	lda #$35
	sta $01

	enable40Mhz()
	enableVIC4Registers()
	disableCIAInterrupts()
	disableC65ROM()

	//Disable IRQ raster interrupts
	//because C65 uses raster interrupts in the ROM
	lda #$00
	sta $d01a

	//Change VIC2 stuff here to save having to disable hot registers
	lda #%00000111
	trb $d016

	cli

	// Enable H320 mode
	lda #$80			//Clear bit7=H640
	trb $d031

	VIC4_SetNumCharacters(SCREEN_WIDTH+1)
	VIC4_SetNumRows(SCREEN_HEIGHT+1)

	VIC4_SetRowWidth(LOGICAL_ROW_SIZE)

	VIC4_SetScreenLocation(SCREEN_BASE)

	lda #<SCREEN_BASE
	sta ChrPtr+0
	lda #>SCREEN_BASE
	sta ChrPtr+1

	lda #<COLOR_RAM
	sta ColPtr+0
	lda #>COLOR_RAM
	sta ColPtr+1
	lda #[COLOR_RAM >>16]
	sta ColPtr+2
	lda #[COLOR_RAM >> 24]
	sta ColPtr+3

	ldx #$00
!oloop:

	txa
	tay

	ldz #$00
!iloop:
	tya
	sta (ChrPtr),z

	and #$07
	sta ((ColPtr)),z

	iny
	inz
	cpz #LOGICAL_ROW_SIZE
	bne !iloop-

	clc
	lda ChrPtr+0
	adc #LOGICAL_ROW_SIZE
	sta ChrPtr+0
	lda ChrPtr+1
	adc #0
	sta ChrPtr+1

	clc
	lda ColPtr+0
	adc #LOGICAL_ROW_SIZE
	sta ColPtr+0
	lda ColPtr+1
	adc #0
	sta ColPtr+1

	inx
	cpx #LOGICAL_NUM_ROWS
	bne !oloop-

mainloop:
	lda #$fe
!:	cmp $d012	// Wait for line 254
	bne !-
!:	cmp $d012	// Wait until we are past 254
	beq !-

	inc FrameCount

	ldx FrameCount
	lda sintable,x
	sta XPos+0
	lda costable,x
	sta YPos+0

	lda YPos+0
	and #$07
	asl
	sta shiftUp

	sec
	lda #$68
	sbc shiftUp:#$00
	sta $d04e
	lda #$00
	sbc #$00
	sta $d04f

	lda XPos+0
	and #$07
	asl
	sta shiftLeft

	sec
	lda #$50
	sbc shiftLeft:#$00
	sta $d04c
	lda #$00
	sbc #$00
	sta $d04d

	lda YPos+0
	sta YCourse+0
	lda YPos+1
	sta YCourse+1

	lsr YCourse+1
	ror YCourse+0
	lsr YCourse+1
	ror YCourse+0
	lsr YCourse+1
	ror YCourse+0

	lda YCourse+0
	tax

	lda XPos+0
	sta XCourse+0
	lda XPos+1
	sta XCourse+1

	lsr XCourse+1
	ror XCourse+0
	lsr XCourse+1
	ror XCourse+0
	lsr XCourse+1
	ror XCourse+0

	clc
	lda RowOffsetsLo,x
	adc XCourse+0
	sta $d060
	lda RowOffsetsHi,x
	adc XCourse+1
	sta $d061

	jmp mainloop

}

RowOffsetsLo:
.fill LOGICAL_NUM_ROWS, <(SCREEN_BASE + (i * LOGICAL_ROW_SIZE))
RowOffsetsHi:
.fill LOGICAL_NUM_ROWS, >(SCREEN_BASE + (i * LOGICAL_ROW_SIZE))

sintable:
	.fill 256, 84 + (sin((i/256) * PI * 2) * 84)
costable:
	.fill 256, 84 + (cos((i/256) * PI * 2) * 84)

* = $4000 "ScreenBase" virtual
SCREEN_BASE:
.fill (LOGICAL_ROW_SIZE * LOGICAL_NUM_ROWS), $00
