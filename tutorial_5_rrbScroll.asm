// ------------------------------------------------------------
//
// Tutorial 2 - 4 way scrolling by changing screen ptr location.
//
// Shows how to scroll the screen in both directions by modifying the TextXPos 
// and TextYPos and then calculating the address of the screen to set into
// ScreenPtr and ColorPtr
//
.file [name="tutorial_5_rrbScroll.prg", segments="Code,Data"]

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
.const SCREEN_HEIGHT = 224

// ------------------------------------------------------------
#import "mega65macros.asm"

// Figure out how many characters wide and high the visible area is
//
.const CHARS_WIDE = (SCREEN_WIDTH / 16) + 2		// NCM chars are 16 pixels wide
												// Add two extra characters to show as we shift off left side
.const NUM_ROWS = (SCREEN_HEIGHT / 8)

// We have a screen size that is larger than the visible area so we can freely
// scroll around it.
//
.const NUM_SCREENS_HIGH = 1

// LOGICAL_ROW_SIZE is the number of bytes the VIC-IV advances each row
//
.const LOGICAL_LAYER_SIZE = (2 + (CHARS_WIDE * 2))

.const LOGICAL_ROW_SIZE = LOGICAL_LAYER_SIZE * 2
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
	ScrollX1:		.byte $00
	ScrollX2:		.byte $00

	ShiftOffsetsL:	.byte $00, $00
	ShiftOffsetsH:	.byte $00, $00

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

	lda #$00
	sta ScrollX1
	sta ScrollX2

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

	lda #$04
    sta $d020

	inc FrameCount

	inc ScrollX1

	lda FrameCount
	and #$01
	bne !+

	inc ScrollX2

!:

	// Layer1 : Calculate how much to shift the layer row off the left size	
	ldx #$00
	lda ScrollX1
	jsr UpdateShiftAmount

	// Layer2 : Calculate how much to shift the layer row off the left size	
	ldx #$01
	lda ScrollX2
	jsr UpdateShiftAmount

	// Update the GOTOX position for all layers using the offsets calculated above
	jsr UpdateLayerPositions

	lda #$00
    sta $d020

	jmp mainloop

}

// Calculate the GOTOX position, this is 0 - (scrollPos & $1f)
//
UpdateShiftAmount:
{
	and #$1f
	sta ul2xscroll
	sec
	lda #0
	sbc ul2xscroll:#$00
	sta ShiftOffsetsL,x
	lda #0
	sbc #0
	and #$03
	sta ShiftOffsetsH,x
	rts
}

// Update the RRB GOTOX value for each of the layers
//
// loop X through each layer
// loop Z through each row
//
UpdateLayerPositions:
{
	.var layerPtr = Tmp			// 16bit
	.var rowPtr = Tmp+2			// 16bit

	// Start layerPtr at top left GOTOX token
	_set16im(SCREEN_BASE, layerPtr)

	// Update all layers
	ldx #$00

layerLoop:

	// Copy layerPtr to rowPtr
	_set16(layerPtr, rowPtr)

	// Update GOTOX position for each row in this layer
	ldz #$00

rowLoop:

	ldy #$00
	lda ShiftOffsetsL,x		// Update Byte0 of layer row
	sta (rowPtr),y
	iny
	lda (rowPtr),y			// Get byte1 of layer row and preserve top 3 bits (FCM char data Y offset)
	and #$e0
	ora ShiftOffsetsH,x		// Update Byte1 of layer row
	sta (rowPtr),y

	// Advance row pointers to the next logical row
	_add16im(rowPtr, LOGICAL_ROW_SIZE, rowPtr)
	
	inz	
	cpz #LOGICAL_NUM_ROWS
	bne rowLoop

	// Advance layer pointer to the next logical layer
	_add16im(layerPtr, LOGICAL_LAYER_SIZE, layerPtr)

	inx
	cpx #$02
	bne layerLoop

	rts
}

// ------------------------------------------------------------
//
#import "mega65system.asm"

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
		lda Palette + $010,x 
		sta $d200,x
		lda Palette + $020,x 
		sta $d300,x

		inx 
		cpx #$10
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
	.import binary "./ncm_test_chr.bin"

.segment Data "Palettes"
Palette:
	.import binary "./ncm_test_pal.bin"

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
			.var choffs = (Chars/64) + (((r&3)*2) + (c&1))
			//Char index
			.byte <choffs,>choffs
		}

		//GOTOX position
		.byte $00,$00

		.for(var c = 0;c < CHARS_WIDE;c++) 
		{
			.var choffs = (Chars/64) + (((r&3)*2) + (c&1)) + 8
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
			// Byte0bit3 = NCM
			// Byte1bit0-3 = Colour 15 index
			.byte $08,$0f
		}

		//GOTOX marker - Byte0bit4=GOTOXMarker, Byte0bit7=Transparent
		.byte $90,$00

		.for(var c = 0;c < CHARS_WIDE;c++) 
		{
			// Byte0bit3 = NCM
			// Byte1bit0-3 = Colour 15 index
			.byte $08,$0f
		}

	}
}

