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
.const SCREEN_HEIGHT = 240

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
.const NUM_SCREENS_WIDE = 2
.const NUM_SCREENS_HIGH = 2

// LOGICAL_ROW_SIZE is the number of bytes the VIC-IV advances each row
//
.const LOGICAL_ROW_SIZE = CHARS_WIDE * NUM_SCREENS_WIDE
.const LOGICAL_NUM_ROWS = CHARS_HIGH * NUM_SCREENS_HIGH

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

	VIC4_SetNumCharacters(CHARS_WIDE+1)
	VIC4_SetNumRows(CHARS_HIGH+1)

	VIC4_SetRowWidth(LOGICAL_ROW_SIZE)

	VIC4_SetScreenPtr(SCREEN_BASE)

	jsr InitScreenColorRAM

	// Set background red so we can see where the screen ends 
	// and the borders start
	lda #$02
	sta $d021

	// Main loop
mainloop:
	// Wait for (H400) rasterline BOT_BORDER
!:	lda $d053
	and #$07
	cmp #>(BOTTOM_BORDER)
	bne !-
    lda #<(BOTTOM_BORDER)
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

	// inc XPos+0
	// inc YPos+0

	// lda #$00
	// sta XPos+0
	// sta YPos+0

	// Set the fine X scroll by moving TextXPos left
	//
	lda XPos+0
	and #$07
#if H320
	asl						// When in H320 mode, move 2x the number of pixels
#endif
	sta shiftLeft

	sec
	lda #<LEFT_BORDER						//#$50
	sbc shiftLeft:#$00
	sta $d04c
	lda #>LEFT_BORDER
	sbc #$00
	sta $d04d

	// Set the fine Y scroll by moving TextYPos up
	//
	lda YPos+0
	and #$07
#if V200
	asl						// When in H200 mode, move 2x the number of pixels
#endif
	sta shiftUp

	sec
	lda #<TOP_BORDER
	sbc shiftUp:#$00
	sta $d04e
	lda #>TOP_BORDER
	sbc #$00
	sta $d04f

	// Now calculate the Y course scroll
	lda YPos+0
	sta YCourse+0
	lda YPos+1
	sta YCourse+1

	// Shift right 3 times to divide by 8
	lsr YCourse+1
	ror YCourse+0
	lsr YCourse+1
	ror YCourse+0
	lsr YCourse+1
	ror YCourse+0

	// Now calculate the X course scroll
	lda XPos+0
	sta XCourse+0
	lda XPos+1
	sta XCourse+1

	// Shift right 3 times to divide by 8
	lsr XCourse+1
	ror XCourse+0
	lsr XCourse+1
	ror XCourse+0
	lsr XCourse+1
	ror XCourse+0

	// We have a lookup table for the byte offset of each row,
	// put Y course into X to access that table
	ldx YCourse+0

	// Using X as the row value, add the X course value to get the
	// offset into both the screen and color RAM
	//
	clc
	lda RowOffsetsLo,x
	adc XCourse+0
	sta screenOffsLo
	sta colorOffsLo
	lda RowOffsetsHi,x
	adc XCourse+1
	sta screenOffsHi
	sta colorOffsHi

	// Set the lower 16bits of screen ptr, 
	// !!! avoid having your screen buffer cross a 64k boundary) !!!
	//
	clc
	lda #<SCREEN_BASE
	adc screenOffsLo:#$00
	sta $d060
	lda #>SCREEN_BASE
	adc screenOffsHi:#$00
	sta $d061

	// Set the lower 16bits of color ptr, 
	// !!! avoid having your color buffer cross a 64k boundary) !!!
	//
	clc
	lda #<COLOR_RAM
	adc colorOffsLo:#$00
	sta $d064
	lda #>COLOR_RAM
	adc colorOffsHi:#$00
	sta $d065

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
.fill (LOGICAL_ROW_SIZE * LOGICAL_NUM_ROWS), $00
