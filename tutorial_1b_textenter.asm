// ------------------------------------------------------------
//
// Tutorial 1 - Setting up the screen.
//
// Shows how to setup both H640&320 horizontal and V400&200 vertically,
// the screen will be centered horizontally and vertically, also handles
// PAL and NTSC.
//
.cpu _45gs02				

// ------------------------------------------------------------
// Defines to describe the screen size
//
// If you use H320 then SCREEN_WIDTH much be <= 360, otherwise <= 720
//#define H320
.const SCREEN_WIDTH = 640

// If you use V200 then SCREEN_HEIGHT much be <= 240, otherwise <= 480
#define V200
.const SCREEN_HEIGHT = 200

// Choose IS_NTSC if you are running in NTSC 60hz mode
//#define IS_NTSC

// ------------------------------------------------------------
#import "mega65macros.asm"

// Figure out how many characters wide and high the visible area is
//
.const CHARS_WIDE = (SCREEN_WIDTH / 8)
.const CHARS_HIGH = (SCREEN_HEIGHT / 8)

// LOGICAL_ROW_SIZE is the number of bytes the VIC-IV advances each row
//
.const LOGICAL_ROW_SIZE = CHARS_WIDE
.const LOGICAL_NUM_ROWS = CHARS_HIGH

// Color RAM is at a fixed base address
//
.const COLOR_RAM = $ff80000

// ------------------------------------------------------------
//
* = $02 "Basepage" virtual
	HexPtr:			.word $0000

	ChrPtr:			.word $0000
	ColPtr:			.dword $00000000

	XPos:			.word $0000
	YPos:			.word $0000

	FrameCount:		.byte $00

	XCourse:		.word $0000
	YCourse:		.word $0000

	Tmp:			.byte $00,$00,$00,$00

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
	lda #%00000111	// Reset XSCL (horizontal fine scroll)
	trb $d016

	cli

	// Setup H640 / H320 mode
	//
	lda #$80
#if H320
	trb $d031			//Clear bit7=H320
#else
	tsb $d031			//Set bit7=H640
#endif

	// Setup V400 / V200 mode
	lda #$08			
#if V200
	trb $d031			//Clear bit3=V200
#else
	tsb $d031			//Set bit3=V400
#endif

	// SDBDRWDLSB,SDBDRWDMSB - Side Border size
	lda #LEFT_BORDER
	sta $d05c
	lda #%00111111
	trb $d05d
	lda #(>LEFT_BORDER) & %00111111
	tsb $d05d

	// TBDRPOS - Top Border position
	lda #<TOP_BORDER
	sta $d048
	lda #%00001111
	trb $d049
	lda #(>TOP_BORDER) & %00001111
	tsb $d049

	// BBDRPOS - Bottom Border position
	lda #<BOTTOM_BORDER
	sta $d04a
	lda #%00001111
	trb $d04b
	lda #(>BOTTOM_BORDER) & %00001111
	tsb $d04b

	// TEXTXPOS - Text X position - position of left most pixel
	lda #<LEFT_BORDER
	sta $d04c
	lda #%00001111
	trb $d04d
	lda #(>LEFT_BORDER) & %00001111
	tsb $d04d

	// TEXTYPOS - Text Y position - position of top most pixel
	lda #<TOP_BORDER
	sta $d04e
	lda #%00001111
	trb $d04f
	lda #(>TOP_BORDER) & %00001111
	tsb $d04f

	VIC4_SetNumCharacters(CHARS_WIDE)
	VIC4_SetNumRows(CHARS_HIGH)

	VIC4_SetRowWidth(LOGICAL_ROW_SIZE)

	VIC4_SetScreenPtr(SCREEN_BASE)

	VIC4_SetCharPtr($3d000)

	lda #$08
	tsb $d069

	jsr InitScreenColorRAM

	// Set background red so we can see where the screen ends 
	// and the borders start
	lda #$02
	sta $d021

	//
	lda #<SCREEN_BASE
	sta ChrPtr+0
	lda #>SCREEN_BASE
	sta ChrPtr+1

	//
	lda #<(SCREEN_BASE + (80*10))
	sta HexPtr+0
	lda #>(SCREEN_BASE + (80*10))
	sta HexPtr+1

	_set32im($8000000, Tmp)
	ldz #$00

	lda #$fc
	sta ((Tmp)),z
	inz
	lda #$fd
	sta ((Tmp)),z
	inz
	lda #$fe
	sta ((Tmp)),z
	inz
	lda #$ff
	sta ((Tmp)),z
	inz

	ldz #$00
	lda ((Tmp)),z
	inz
	jsr AddHexOutput
	lda ((Tmp)),z
	inz
	jsr AddHexOutput
	lda ((Tmp)),z
	inz
	jsr AddHexOutput
	lda ((Tmp)),z
	inz
	jsr AddHexOutput

	ldy #$00

keyloop:
	lda $d610
	beq keyloop
	sta $d610

	jsr AddHexOutput

	cmp #$14
	bne nodel

	dew ChrPtr
	lda #$20
	sta (ChrPtr),y
	bra keyloop

nodel:
	cmp #$60
	bcc !+
	sec
	sbc #$60
!:
	sta (ChrPtr),y
	inw ChrPtr

	bra keyloop

	// Main loop
mainloop:
	// Wait for (H400) rasterline $07
!:	lda $d053
	and #$07
	bne !-
    lda #$04
	cmp $d052 
    bne !-
!:	cmp $d052 
    beq !-

    inc $d020

	inc FrameCount

    dec $d020

	jmp mainloop

}

AddHexOutput: {
	pha	
	// draw upper nibble
	lsr
	lsr
	lsr
	lsr
	tax
	lda HexTable,x
	sta (HexPtr),y
	inw HexPtr
	pla

	pha
	// draw lower nibble
	and #$0f
	tax
	lda HexTable,x
	sta (HexPtr),y
	inw HexPtr
	pla

	rts
}

// ------------------------------------------------------------
// Routine to initialize the screen and color RAM with data
//
InitScreenColorRAM: {
	//
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

	lda #$00
	sta Tmp

	ldx #$00
!oloop:

	ldz #$00
!iloop:
	ldy Tmp
	lda Test,y
	bne !skip+

	ldy #$00
	sty Tmp
	lda Test,y

!skip:
	sta (ChrPtr),z

	inc Tmp

	lda #$01
	and #$07
	sta ((ColPtr)),z

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

	rts
}

// $0.40
// $1.50
// $1.43
// $0.50
// $0.58

.encoding "screencode_mixed"
HexTable:
.text "0123456789ABCDEF"

Test:
// .text "This is a test of the font, "
.text " "
.byte $00

Sample:
.text "How do we convert"
.byte $00

.print "Sample = " + toHexString(Sample)

RowOffsetsLo:
.fill LOGICAL_NUM_ROWS, <(i * LOGICAL_ROW_SIZE)
RowOffsetsHi:
.fill LOGICAL_NUM_ROWS, >(i * LOGICAL_ROW_SIZE)

sintable:
	.fill 256, 84 + (sin((i/256) * PI * 2) * 84)
costable:
	.fill 256, 84 + (cos((i/256) * PI * 2) * 84)

* = $4000 "ScreenBase" virtual
SCREEN_BASE:
.fill (LOGICAL_ROW_SIZE * LOGICAL_NUM_ROWS), $00
