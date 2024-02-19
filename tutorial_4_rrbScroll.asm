// ------------------------------------------------------------
//
// Tutorial 2 - 4 way scrolling by changing screen ptr location.
//
// Shows how to scroll the screen in both directions by modifying the TextXPos 
// and TextYPos and then calculating the address of the screen to set into
// ScreenPtr and ColorPtr
//
.file [name="tutorial_4_rrbScroll.prg", segments="Code,Data"]

// Color RAM is at a fixed base address
//
.const COLOR_RAM = $ff80000

// Screen RAM will be put in bank 2
//
.const SCREEN_RAM = $20000

// ------------------------------------------------------------
//
.segmentdef Zeropage [start=$02, min=$02, max=$fb, virtual]
.segmentdef Code [start=$2001, max=$cfff]
.segmentdef Data [start=$4000, max=$cfff]
.segmentdef BSS [startAfter="Data", max=$cfff, virtual]

.cpu _45gs02				

// ------------------------------------------------------------
// Defines to describe the screen size
//
// If you use H320 then SCREEN_WIDTH much be <= 360, otherwise <= 720
#define H320
.const SCREEN_WIDTH = 320

// If you use V200 then SCREEN_HEIGHT much be <= 240
#define V200
.const SCREEN_HEIGHT = 224

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
.const LOGICAL_ROW_SIZE = (2 + (CHARS_WIDE * 2))
.const LOGICAL_NUM_ROWS = NUM_ROWS * NUM_SCREENS_HIGH

.print "LOGICAL_ROW_SIZE = " + LOGICAL_ROW_SIZE
.print "NUM_CHARS = " + LOGICAL_ROW_SIZE / 2

.print "SCREEN_BASE = " + toHexString(SCREEN_BASE)

// ------------------------------------------------------------
//
.segment Zeropage "Main zeropage"
	Tmp:			.word $0000,$0000
	Tmp1:			.word $0000,$0000

	FrameCount:		.byte $00

// ------------------------------------------------------------
//
.segment Code
BasicUpstart65(Entry)
* = $2016

.segment Code "Entry"
Entry: {
	jsr System.InitM65

	// Update screen positioning based on PAL/NTSC
	jsr System.CenterFrameHorizontally
	jsr System.CenterFrameVertically

	jsr System.InitVideoMode

	VIC4_SetRowWidth(LOGICAL_ROW_SIZE)
	VIC4_SetNumCharacters(LOGICAL_ROW_SIZE/2)
	VIC4_SetNumRows(NUM_ROWS)

	VIC4_SetScreenPtr(SCREEN_BASE)

	jsr InitPalette
	jsr CopyColors

	lda #$00
	sta $d020
	sta $d021

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


.namespace System
{
	//--------------------------------------------------------
	//
	.segment Zeropage "System ZP"
	TopBorder:		.word $0000
	BotBorder:		.word $0000
	IRQTopPos:		.word $0000
	IRQBotPos:		.word $0000

	.segment Code "System Code"
	InitM65:
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

		// Set XSCL to 0, setting here to save having to disable hot registers
		lda #%00000111
		trb $d016

		// Disable hot register so VIC2 registers 
		lda #$80		
		trb $d05d			//Clear bit7=HOTREG

		cli

		rts
	}

	InitVideoMode:
	{
	    // Set RASLINE0 to 0 for the first VIC-II rasterline
	    lda #%00111111
	    trb $d06f

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

		// Init H320 flag
		lda #$80			
#if H320
		trb $d031			//Clear bit7=H640
#else
		tsb $d031			//Set bit7=H640
#endif

		// Enable Super Extended Attributes and mono chars < $ff
		lda #%00000101		//Set bit2=FCM for chars >$ff,  bit0=16 bit char indices (SEAM)
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

		// Work around VHDL issue
		// 
		// If running on real hardware, shift screen left SCALED pixel
		lda $d60f
		and #%00100000
		beq !+
		_sub16im(charXPos, HPIXELSCALE, charXPos)
	!:

		// TEXTXPOS - Text X Pos
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
		_set16im(((NUM_ROWS * 8) * VPIXELSCALE)/2, halfCharHeight)

		// Figure out the vertical center of the screen

		// PAL values
		_set16im(304, verticalCenter)

		bit $d06f
		bpl isPal

		// NTSC values
		_set16im(242, verticalCenter)

	isPal:

		_sub16(verticalCenter, halfCharHeight, TopBorder)
		_add16(verticalCenter, halfCharHeight, BotBorder)

		_set16(TopBorder, charYPos)

		// Work around VHDL issue
		// 
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

		// convert from V400 units to raster lines
		lsr IRQTopPos+1
		ror IRQTopPos+0

		_add16im(BotBorder, 1, IRQBotPos)

		// convert from V400 units to raster lines
		lsr IRQBotPos+1
		ror IRQBotPos+0

		rts
	}

}

// ------------------------------------------------------------
//
InitPalette: {
		//Bit pairs = CurrPalette, TextPalette, SpritePalette, AltPalette
		lda #%00000000 //Edit=%00, Text = %00, Sprite = %00, Alt = %00
		sta $d070 

		ldx #$00
	!:
		lda Palette + $000,x 	// background
		sta $d100,x
		lda Palette + $100,x 
		sta $d200,x
		lda Palette + $200,x 
		sta $d300,x

		inx 
		cpx #$00
		bne !-

		// Ensure index 0 is black
		lda #$00
		sta $d100
		sta $d200
		sta $d300

		rts
}

// ------------------------------------------------------------
//
CopyColors: 
{
	RunDMAJob(Job)
	rts 
Job:
	DMAHeader($00, COLOR_RAM>>20)
	DMACopyJob(COLOR_BASE, COLOR_RAM, LOGICAL_ROW_SIZE * NUM_ROWS, false, false)
}

// ------------------------------------------------------------
//
.segment Data "Chars"
.align 64
Chars:
	.import binary "./fcm_test_chr.bin"

.segment Data "Palettes"
Palette:
	.import binary "./fcm_test_pal.bin"

.print "Chars = " + toHexString(Chars)

// ------------------------------------------------------------
//
.segment Data "ScreenData"
SCREEN_BASE:
{
	.for(var r = 0;r < LOGICAL_NUM_ROWS;r++) 
	{
		//GOTOX position
		.byte $00,$00

		.for(var c = 0;c < CHARS_WIDE;c++) 
		{
			.var choffs = (Chars/64) + (((r&3)*4) + (c&3))
			//Char index
			.byte <choffs,>choffs
		}
	}
}

// ------------------------------------------------------------
//
.segment Data "ColorData"
COLOR_BASE:
{
	.for(var r = 0;r < LOGICAL_NUM_ROWS;r++) 
	{
		//GOTOX marker - Byte0bit4=GOTOXMarker
		.byte $10,$00

		.for(var c = 0;c < CHARS_WIDE;c++) 
		{
			.byte $00,$00
		}
	}
}

