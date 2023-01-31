// ------------------------------------------------------------
//
// Tutorial 2 - 4 way scrolling by changing screen ptr location.
//
// Shows how to scroll the screen in both directions by modifying the TextXPos 
// and TextYPos and then calculating the address of the screen to set into
// ScreenPtr and ColorPtr
//
.file [name="tutorial_4_ncm.prg", segments="Code,Data"]

// ------------------------------------------------------------
//
.segmentdef Zeropage [start=$02, min=$02, max=$fb, virtual]
.segmentdef Code [start=$2001, max=$cfff]
.segmentdef Data [startAfter="Code", max=$cfff]
.segmentdef BSS [startAfter="Data", max=$cfff, virtual]

.cpu _45gs02				

// ------------------------------------------------------------
// Defines to describe the screen size
//
// If you use H320 then SCREEN_WIDTH much be <= 360, otherwise <= 720
#define H320
.const SCREEN_WIDTH = 320

// If you use V200 then SCREEN_HEIGHT much be <= 240, otherwise <= 480
#define V200
.const SCREEN_HEIGHT = 200

// ------------------------------------------------------------
#import "mega65macros.asm"

// Figure out how many characters wide and high the visible area is
//
.const CHARS_WIDE = (SCREEN_WIDTH / 8)
.const NUM_ROWS = (SCREEN_HEIGHT / 8)

// We have a screen size that is larger than the visible area so we can freely
// scroll around it.
//
.const NUM_SCREENS_HIGH = 1

// LOGICAL_ROW_SIZE is the number of bytes the VIC-IV advances each row
//
.const LOGICAL_ROW_SIZE = ((CHARS_WIDE * 2))
.const LOGICAL_NUM_ROWS = NUM_ROWS * NUM_SCREENS_HIGH

// Color RAM is at a fixed base address
//
.const COLOR_RAM = $ff80000

.print "LOGICAL_ROW_SIZE = " + LOGICAL_ROW_SIZE
.print "SCREEN_BASE = " + toHexString(SCREEN_BASE)

// ------------------------------------------------------------
//
.segment Zeropage "Main zeropage"
	Tmp:			.word $0000,$0000
	Tmp1:			.word $0000,$0000
	Tmp2:			.word $0000,$0000
	Tmp3:			.word $0000,$0000
	Tmp4:			.word $0000,$0000
	Tmp5:			.word $0000,$0000

	ChrPtr:			.word $0000
	ColPtr:			.dword $00000000

	XPos:			.word $0000
	YPos:			.word $0000

	FrameCount:		.byte $00

	XCourse:		.word $0000
	YCourse:		.word $0000

// ------------------------------------------------------------
//
.segment Code
BasicUpstart65(Entry)
* = $2016

.segment Code "Entry"
Entry: {
	jsr System.Initialization1

	// Update screen positioning based on PAL/NTSC
	jsr System.CenterFrameHorizontally
	jsr System.CenterFrameVertically

	jsr System.Initialization2

	VIC4_SetRowWidth(LOGICAL_ROW_SIZE)
	VIC4_SetNumCharacters(LOGICAL_ROW_SIZE/2)
	VIC4_SetNumRows(NUM_ROWS)

	VIC4_SetScreenPtr(SCREEN_BASE)

	jsr InitScreenColorRAM

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

	lda #$00
	sta XPos+0
	sta YPos+0

	// Set the fine X scroll by moving TextXPos left
	//
// 	lda XPos+0
// 	and #$07
// #if H320
// 	asl						// When in H320 mode, move 2x the number of pixels
// #endif
// 	sta shiftLeft

	// sec
	// lda #<LEFT_BORDER						//#$50
	// sbc shiftLeft:#$00
	// sta $d04c
	// lda #>LEFT_BORDER
	// sbc #$00
	// sta $d04d

	// Set the fine Y scroll by moving TextYPos up
	//
// 	lda YPos+0
// 	and #$07
// #if V200
// 	asl						// When in H200 mode, move 2x the number of pixels
// #endif
// 	sta shiftUp

	// sec
	// lda #<TOP_BORDER
	// sbc shiftUp:#$00
	// sta $d04e
	// lda #>TOP_BORDER
	// sbc #$00
	// sta $d04f

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
	// clc
	// lda RowOffsetsLo,x
	// adc XCourse+0
	// sta screenOffsLo
	// sta colorOffsLo
	// lda RowOffsetsHi,x
	// adc XCourse+1
	// sta screenOffsHi
	// sta colorOffsHi

	// Set the lower 16bits of screen ptr, 
	// !!! avoid having your screen buffer cross a 64k boundary) !!!
	//
	// clc
	// lda #<SCREEN_BASE
	// adc screenOffsLo:#$00
	// sta $d060
	// lda #>SCREEN_BASE
	// adc screenOffsHi:#$00
	// sta $d061

	// Set the lower 16bits of color ptr, 
	// !!! avoid having your color buffer cross a 64k boundary) !!!
	//
	// clc
	// lda #<COLOR_RAM
	// adc colorOffsLo:#$00
	// sta $d064
	// lda #>COLOR_RAM
	// adc colorOffsHi:#$00
	// sta $d065

    dec $d020

	jmp mainloop

}


.namespace System
{
	//--------------------------------------------------------
	//
	.segment Zeropage "System ZP"
	TopBorder:		.word $0000
	BotBorder:		.word $0000
	IRQTopPos:		.word $0000
	IRQBotPos:		.word $0000
	SprYBase:		.byte $00

	.segment Code "System Code"
	Initialization1:
	{
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

	    // Set RASLINE0 to 0 for the first VIC-II rasterline
	    lda #%00111111
	    trb $d06f

		//Disable hot register so VIC2 registers 
		lda #$80		
		trb $d05d			//Clear bit7=HOTREG

		cli

		rts
	}

	Initialization2:
	{

		// Disable VIC3 ATTR register to enable 8bit color
		lda #$20			//Clear bit5=ATTR
		trb $d031

		// Enable RAM palettes
		lda #$04			//Set bit2=PAL
		tsb $d030

		// Enable RRB double buffer
		lda #$80			//Clear bit7=NORRDEL
		trb $d051

		// Enable double line RRB to double the time for RRB operations 
		lda #$08			//Set bit3=V400
		tsb $d031
		lda #$40    		//Set bit6=DBLRR
		tsb $d051
		lda #$00    		//Set CHRYSCL = 0
		sta $d05b

		// Enable H320 mode, Super Extended Attributes and mono chars < $ff
		lda #$80			//Clear bit7=H640
		trb $d031
		lda #%00000101		//Set bit2=FCM for chars >$ff,  bit0=16 bit char indices
		tsb $d054

		rts
	}

	CenterFrameHorizontally:
	{
		.var charXPos = Tmp				// 16bit

		_set16im(LEFT_BORDER, charXPos)

		// SDBDRWDLSB,SDBDRWDMSB - Side Border size
		lda charXPos+0
		sta $d05c
		lda #%00111111
		trb $d05d
		lda charXPos+1
		and #%00111111
		tsb $d05d

		// TEXTXPOS - Text X Pos

		// If running on real hardware, shift screen left SCALED pixel
		lda $d60f
		and #%00100000
		beq !+
		_sub16im(charXPos, HPIXELSCALE, charXPos)
	!:

		lda charXPos+0
		sta $d04c
		lda #%00001111
		trb $d04d
		lda charXPos+1
		and #%00001111
		sta $d04d

		rts
	}
	CenterFrameVertically: 
	{
		.var verticalCenter = Tmp			// 16bit
		.var halfCharHeight = Tmp+2			// 16bit
		.var charYPos = Tmp1				// 16bit

		// The half height of the screen in rasterlines is (charHeight / 2) * 2
		_set16im(NUM_ROWS * 8, halfCharHeight)

		// Figure out the vertical center of the screen

		// PAL values
		_set16im(304, verticalCenter)
		_set8im($fe, SprYBase)

		bit $d06f
		bpl isPal

		// NTSC values
		_set16im(242, verticalCenter)
		_set8im($16, SprYBase)

	isPal:

		_sub16(verticalCenter, halfCharHeight, TopBorder)
		_add16(verticalCenter, halfCharHeight, BotBorder)

		_set16(TopBorder, charYPos)

		// hack!!
		// If we are running on real hardware then adjust char Y start up to avoid 2 pixel Y=0 bug
		lda $d60f
		and #%00100000
		beq !+

		_add16im(TopBorder, 1, TopBorder)
		_add16im(BotBorder, 1, BotBorder)
		_sub16im(charYPos, 2, charYPos)

	!:

		// Set these values on the hardware
		// TBDRPOS - Top Border
		lda TopBorder+0
		sta $d048
		lda #%00001111
		trb $d049
		lda TopBorder+1
		tsb $d049

		// BBDRPOS - Bot Border
		lda BotBorder+0
		sta $d04a
		lda #%00001111
		trb $d04b
		lda BotBorder+1
		tsb $d04b

		// TEXTYPOS - CharYStart
		lda charYPos+0
		sta $d04e
		lda #%00001111
		trb $d04f
		lda charYPos+1
		tsb $d04f

		_add16im(TopBorder, 1, IRQTopPos)

		lsr IRQTopPos+1
		ror IRQTopPos+0

		_add16im(BotBorder, 1, IRQBotPos)

		lsr IRQBotPos+1
		ror IRQBotPos+0

		clc
		lda SprYBase
		adc IRQTopPos+0
		sta SprYBase

		rts
	}

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

	// layer 1
	ldy #$00
!iloop1:
	txa
//	lda #$01
	sta (ChrPtr),z
	lda #$00
	sta ((ColPtr)),z
	inz

	lda #$00
	sta (ChrPtr),z
	lda #$0e
	sta ((ColPtr)),z
	inz

	iny
	cpy #CHARS_WIDE
	bne !iloop1-

	// advance to next row
	_add16im(ChrPtr, LOGICAL_ROW_SIZE, ChrPtr)
	_add16im(ColPtr, LOGICAL_ROW_SIZE, ColPtr)

	inx
	cpx #LOGICAL_NUM_ROWS
	lbne !oloop-

	rts
}

.segment Data "Rows"
RowOffsetsLo:
.fill LOGICAL_NUM_ROWS, <(i * LOGICAL_ROW_SIZE)
RowOffsetsHi:
.fill LOGICAL_NUM_ROWS, >(i * LOGICAL_ROW_SIZE)

sintable:
	.fill 256, 84 + (sin((i/256) * PI * 2) * 84)
costable:
	.fill 256, 84 + (cos((i/256) * PI * 2) * 84)

.segment BSS "ScreenBase"
SCREEN_BASE:
	.fill (LOGICAL_ROW_SIZE * LOGICAL_NUM_ROWS), 0

