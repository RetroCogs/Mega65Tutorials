// ------------------------------------------------------------
//
// Tutorial 2 - 4 way scrolling by changing screen ptr location.
//
// Shows how to scroll the screen in both directions by modifying the TextXPos 
// and TextYPos and then calculating the address of the screen to set into
// ScreenPtr and ColorPtr
//
.cpu _45gs02				

// ------------------------------------------------------------
// Defines to describe the screen size
//
// If you use H320 then SCREEN_WIDTH much be <= 360, otherwise <= 720
#define H320
.const SCREEN_WIDTH = 320

// If you use V200 then SCREEN_HEIGHT much be <= 240, otherwise <= 480
#define V200
.const SCREEN_HEIGHT = 224

// Choose IS_NTSC if you are running in NTSC 60hz mode
//#define IS_NTSC

// ------------------------------------------------------------
#import "mega65macros.asm"

// Figure out how many characters wide and high the visible area is
//
.const CHARS_WIDE = (SCREEN_WIDTH / 8)
.const CHARS_HIGH = (SCREEN_HEIGHT / 8)

// We have a screen size that is larger than the visible area so we can freely
// scroll around it.
//
.const NUM_SCREENS_HIGH = 1

// LOGICAL_ROW_SIZE is the number of bytes the VIC-IV advances each row
//
.const LOGICAL_ROW_SIZE = (1 + CHARS_WIDE + 1 + CHARS_WIDE + 2) * 2
.const LOGICAL_NUM_ROWS = CHARS_HIGH * NUM_SCREENS_HIGH

.const CHARCOUNT = LOGICAL_ROW_SIZE / 2

// Color RAM is at a fixed base address
//
.const COLOR_RAM = $ff80000

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

	lda #$05    //Enable 16 bit char numbers (bit0) and 
	sta $d054   //full color for chars>$ff (bit2)

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

	// TEXTYPOS
	lda #<TEXTYPOS
	sta $d04e
	lda #>TEXTYPOS
	sta $d04f

	VIC4_SetNumCharacters(CHARCOUNT)
	VIC4_SetNumRows(CHARS_HIGH)

	VIC4_SetRowWidth(LOGICAL_ROW_SIZE)

	VIC4_SetScreenPtr(SCREEN_BASE)

	jsr InitScreenColorRAM

	lda #$05
	sta $d020

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

	ldx FrameCount
	lda sintable,x
	sta XPos+0
	lda costable,x
	sta YPos+0

    dec $d020

	jmp mainloop

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

	ldx #$00
!oloop:

	ldz #$00

	// gotox - 0
	lda #$ff
	sta (ChrPtr),z
	lda #$10
	sta ((ColPtr)),z
	inz

	lda #$03
	sta (ChrPtr),z
	lda #$00
	sta ((ColPtr)),z
	inz

	// layer 1
	ldy #$00
!iloop1:
	lda #$66
	sta (ChrPtr),z
	lda #$00
	sta ((ColPtr)),z
	inz

	lda #$00
	sta (ChrPtr),z
	lda #$00
	sta ((ColPtr)),z
	inz

	iny
	cpy #CHARS_WIDE
	bne !iloop1-

	// gotox - 0
	lda #$ff
	sta (ChrPtr),z
	lda #$90
	sta ((ColPtr)),z
	inz

	lda #$03
	sta (ChrPtr),z
	lda #$00
	sta ((ColPtr)),z
	inz

	// layer 2
	ldy #$00
!iloop2:
	lda #$66
	sta (ChrPtr),z
	lda #$00
	sta ((ColPtr)),z
	inz

	lda #$00
	sta (ChrPtr),z
	lda #$07
	sta ((ColPtr)),z
	inz

	iny
	cpy #CHARS_WIDE
	bne !iloop2-

	// gotox - SCREEN_WIDTH
	lda #<SCREEN_WIDTH
	sta (ChrPtr),z
	lda #$90
	sta ((ColPtr)),z
	inz

	lda #>SCREEN_WIDTH
	sta (ChrPtr),z
	lda #$00
	sta ((ColPtr)),z
	inz

	// end char
	lda #$00
	sta (ChrPtr),z
	lda #$00
	sta ((ColPtr)),z
	inz

	lda #$00
	sta (ChrPtr),z
	lda #$00
	sta ((ColPtr)),z
	inz

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
	lbne !oloop-

	rts
}

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
	.fill (LOGICAL_ROW_SIZE * LOGICAL_NUM_ROWS) * 2, 0

