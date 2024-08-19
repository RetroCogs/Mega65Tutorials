// ------------------------------------------------------------
//
// Tutorial 2 - 4 way scrolling by changing screen ptr location.
//
// Shows how to scroll the screen in both directions by modifying the TextXPos 
// and TextYPos and then calculating the address of the screen to set into
// ScreenPtr and ColorPtr
//
.file [name="tutorial_3a_fcm_rrb.prg", segments="Code,Data"]

// Color RAM is at a fixed base address
//
.const COLOR_RAM = $ff80000

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
.const SCREEN_HEIGHT = 192

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
.const LOGICAL_ROW_SIZE = (2 + (CHARS_WIDE * 2)) + (2 + 2) + (2 + 2) + (2 + 2) + (2 + 2) + (2)
.const LOGICAL_NUM_ROWS = NUM_ROWS * NUM_SCREENS_HIGH

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

// ------------------------------------------------------------
//
#import "mega65system.asm"

// ------------------------------------------------------------
//
InitPalette: {
		lda $d070
		and #%00111111
		ora #%00000000
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
		// lda #$00
		// sta $d100
		// sta $d200
		// sta $d300

		lda $d070
		and #%00111111
		ora #%01000000
		sta $d070 

		ldx #$00
	!:
		lda Palette + $000,x 	// background
		sta $d100,x
		lda Palette + $000,x 
		sta $d200,x
		lda Palette + $000,x 
		sta $d300,x

		inx 
		cpx #$00
		bne !-

		// Ensure index 0 is black
		// lda #$00
		// sta $d100
		// sta $d200
		// sta $d300

		lda $d070
		and #%11001100
		ora #%00000001
		sta $d070 

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
    .var scrpos = SCREEN_WIDTH/2 - 20
    .var scrpos2 = SCREEN_WIDTH/2 - 8
    .var scrpos3 = SCREEN_WIDTH/2 + 8
    .var scrpos4 = SCREEN_WIDTH/2 + 20

	.for(var r = 0;r < LOGICAL_NUM_ROWS;r++) 
	{
		//GOTOX position
		.byte $00,$00

		.for(var c = 0;c < CHARS_WIDE;c++) 
		{
			.var choffs = (Chars/64) + (((r&7)*8) + (c&7))
			//Char index
			.byte <choffs,>choffs
		}

        .var aroffs = (Chars/64) + 64

		//GOTOX position
		.byte <scrpos,>scrpos
        //Char index
        .byte <aroffs,>aroffs

		//GOTOX position
		.byte <scrpos2,>scrpos2
        //Char index
        .byte <aroffs,>aroffs

		//GOTOX position
		.byte <scrpos3,>scrpos3
        //Char index
        .byte <aroffs,>aroffs

		//GOTOX position
		.byte <scrpos4,>scrpos4
        //Char index
        .byte <aroffs,>aroffs

        // End of Line, place a GOTOX marker at SCREEN_WIDTH
		//GOTOX position
		.byte <SCREEN_WIDTH,>SCREEN_WIDTH
	}
}

// ------------------------------------------------------------
//
.segment Data "ColorData"
COLOR_BASE:
{
	.for(var r = 0;r < LOGICAL_NUM_ROWS;r++) 
	{
		.var altpal = $00
		.var altpal2 = $00
		.if((r & 8) != 0)
		{
			// Byte0bit5=Use Alt Palette
			.eval altpal = $20
			.eval altpal2 = $60
		}

		//GOTOX marker - Byte0bit4=GOTOXMarker
		.byte $10+$00+altpal,altpal2	//%10101010

		.for(var c = 0;c < CHARS_WIDE;c++) 
		{
			// Byte1bit0-7 = Colour 255 index
			.byte $00,$ff
		}

		//GOTOX marker - Byte0bit4=GOTOXMarker
		.byte $10,$00
        // Byte1bit0-7 = Colour 255 index
        .byte $00,$ff

		//GOTOX marker - byte0bit7=Transparent, Byte0bit4=GOTOXMarker
		.byte $90,$00
        // Byte1bit0-7 = Colour 255 index
        .byte $00,$ff

		//GOTOX marker - Byte0bit4=GOTOXMarker
		.byte $10,$00
        // Byte0bit7 = FLIP
        // Byte1bit0-7 = Colour 255 index
        .byte $80,$ff

		//GOTOX marker - byte0bit7=Transparent, Byte0bit4=GOTOXMarker
		.byte $90,$00
        // Byte0bit7 = FLIP
        // Byte1bit0-7 = Colour 255 index
        .byte $80,$ff

        // End of Line, place a GOTOX marker at SCREEN_WIDTH
		//GOTOX marker - Byte0bit4=GOTOXMarker
		.byte $10+$00+altpal,altpal2	//%10101010
	}
}

