// ------------------------------------------------------------
//
// Tutorial 5 - Horizonral scrolling of 2 layers using RRB.
//
// Shows how to scroll the screen for 2 layers of background, using RRB each layer can
// be scrolled independantly at any speed.
//
// Char and Attrib data are DMA'd into the screen RRB layout and the GOTOX position for 
// each row is set accordingly.
//
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

.segmentdef ScreenRam [start=$50000, virtual]

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
.const CHARS_WIDE = (SCREEN_WIDTH / 16) + 1		// NCM chars are 16 pixels wide
												// Add one extra characters to show as we shift off left side
.const NUM_ROWS = (SCREEN_HEIGHT / 8)

// LOGICAL_LAYER_SIZE is the number of bytes the VIC-IV uses for one layer
//
.const LOGICAL_LAYER_SIZE = (2 + (CHARS_WIDE * 2))

// LOGICAL_ROW_SIZE is the number of bytes the VIC-IV advances each row
//
.const LOGICAL_ROW_SIZE = LOGICAL_LAYER_SIZE * 2	// 2 layers
.const LOGICAL_NUM_ROWS = NUM_ROWS

// ------------------------------------------------------------
//
.const MAP_WIDTH = (1024 / 16)
.const MAP_HEIGHT = (SCREEN_HEIGHT / 8)

// MAP_LOGICAL_SIZE is the number of bytes each row takes in the map / attrib data
//
.const MAP_LOGICAL_SIZE = MAP_WIDTH * 2

// ------------------------------------------------------------
//
.segment Zeropage "Main zeropage"
	Tmp:			.word $0000,$0000
	Tmp1:			.word $0000,$0000
	Tmp2:			.word $0000,$0000
	Tmp3:			.word $0000,$0000
	Tmp4:			.word $0000,$0000

	FrameCount:		.byte $00
	ScrollX1:		.byte $00,$00
	ScrollX2:		.byte $00,$00

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

	VIC4_SetScreenPtr(ScreenRam)

	jsr InitPalette

	jsr InitScreenColorRAM

	lda #$00
	sta $d020
	sta $d021

	_set16im(0, ScrollX1)
	_set16im(0, ScrollX2)

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

	// Do some sin/cos based scrolling for the 2 layers
	ldx FrameCount
	lda sintable,x
	sta ScrollX1
	lda costable,x
	sta ScrollX2

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

	// Update the char / attrib data using DMA
	jsr UpdateLayerData.UpdateLayer1
	jsr UpdateLayerData.UpdateLayer2
	
	lda #$00
    sta $d020

	jmp mainloop

}

// ------------------------------------------------------------
// Calculate the GOTOX position, this is 0 - (scrollPos & $0f)
//
UpdateShiftAmount:
{
	and #$0f
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

// ------------------------------------------------------------
// Update the RRB GOTOX value for each of the layers
//
// loop X through each layer
// loop Y through each row
//
UpdateLayerPositions:
{
	.var layerPtr = Tmp			// 32bit
	.var rowPtr = Tmp1			// 32bit

	// Start layerPtr at top left GOTOX token
	_set32im(ScreenRam, layerPtr)

	// Update all layers
	ldx #$00

layerLoop:

	// Copy layerPtr to rowPtr
	_set32(layerPtr, rowPtr)

	// Update GOTOX position for each row in this layer
	ldy #$00

rowLoop:

	ldz #$00
	lda ShiftOffsetsL,x		// Update Byte0 of layer row
	sta ((rowPtr)),z
	inz
	lda ((rowPtr)),z		// Get byte1 of layer row and preserve top 3 bits (FCM char data Y offset)
	and #$e0
	ora ShiftOffsetsH,x		// Update Byte1 of layer row
	sta ((rowPtr)),z

	// Advance row pointers to the next logical row
	_add32im(rowPtr, LOGICAL_ROW_SIZE, rowPtr)
	
	iny	
	cpy #LOGICAL_NUM_ROWS
	bne rowLoop

	// Advance layer pointer to the next logical layer
	_add32im(layerPtr, LOGICAL_LAYER_SIZE, layerPtr)

	inx
	cpx #$02
	bne layerLoop

	rts
}

// ------------------------------------------------------------
// To update the char / attrib data for the scrolling layers we need to DMA
// data from the Map into the screen, this is done as a DMA for each row,
// one for chars and one for attribs.
//
UpdateLayerData: {
	.var src_tile_ptr = Tmp			// 32bit
	.var src_attrib_ptr = Tmp1		// 32bit

	.var dst_offset = Tmp2			// 16bit
	.var copy_length = Tmp2+2		// 16bit

	.var src_offset = Tmp3			// 16bit
	.var src_stride = Tmp3+2		// 16bit

	UpdateLayer1: {
		_set32im(MapRam, src_tile_ptr)
		_set32im(AttribRam, src_attrib_ptr)

		_set16im(MAP_LOGICAL_SIZE, src_stride)

		// Source offset is (ScrollX1 >> 4) << 1
		_set16(ScrollX1, src_offset)

		lsr src_offset+1
		ror src_offset+0
		lsr src_offset+1
		ror src_offset+0
		lsr src_offset+1
		ror src_offset+0
		lda src_offset+0
		and #$fe
		sta src_offset+0

		// Copy into char after GOTOX
		_set16im(2, dst_offset)

		_set16im(CHARS_WIDE * 2, copy_length)

		jsr CopyLayerChunks

		rts
	}

	UpdateLayer2: {
		_set32im(MapRam2, src_tile_ptr)
		_set32im(AttribRam, src_attrib_ptr)

		_set16im(MAP_LOGICAL_SIZE, src_stride)

		// Source offset is (ScrollX2 >> 4) << 1
		_set16(ScrollX2, src_offset)

		lsr src_offset+1
		ror src_offset+0
		lsr src_offset+1
		ror src_offset+0
		lsr src_offset+1
		ror src_offset+0
		lda src_offset+0
		and #$fe
		sta src_offset+0

		// Copy into char after GOTOX on the second layer
		_set16im(2 + LOGICAL_LAYER_SIZE, dst_offset)

		_set16im(CHARS_WIDE * 2, copy_length)

		jsr CopyLayerChunks

		rts
	}

	// Loop for each row in both chars and attribs and DMA one screen wide piece of data
	//
	CopyLayerChunks: {
		_set16(copy_length, tileLength)
		_set16(copy_length, attribLength)

		// Tiles are copied from Bank (MapRam>>20) to (ScreenRam>>20)
		lda #[MapRam>>20]
		sta tileSrcBank
		lda #[ScreenRam>>20]
		sta tileDestBank

		// Attribs are copied from Bank (AttribRam>>20) to (COLOR_RAM>>20)
		lda #[AttribRam>>20]
		sta attribSrcBank
		lda #[COLOR_RAM>>20]
		sta attribDestBank

		// DMA tile rows
		//
		clc
		lda src_tile_ptr+0
		adc src_offset+0
		sta tileSource+0
		lda src_tile_ptr+1
		adc src_offset+1
		sta tileSource+1
		lda src_tile_ptr+2
		and #$0f
		sta tileSource+2

		clc
		lda #<ScreenRam
		adc dst_offset+0
		sta tileDest+0
		lda #>ScreenRam
		adc dst_offset+1
		sta tileDest+1
		lda #[ScreenRam >> 16]
		and #$0f
		sta tileDest+2

		ldx #$00
	!tloop:
		RunDMAJob(TileJob)

		_add16(tileSource, src_stride, tileSource)
		_add16im(tileDest, LOGICAL_ROW_SIZE, tileDest)

		inx
		cpx #NUM_ROWS
		bne !tloop-

		// DMA attribute rows
		//
		clc
		lda src_attrib_ptr+0
		adc src_offset+0
		sta attribSource+0
		lda src_attrib_ptr+1
		adc src_offset+1
		sta attribSource+1
		lda src_attrib_ptr+2
		and #$0f
		sta attribSource+2

		clc
		lda #<COLOR_RAM
		adc dst_offset+0
		sta attribDest+0
		lda #>COLOR_RAM
		adc dst_offset+1
		sta attribDest+1
		lda #[COLOR_RAM >> 16]
		and #$0f
		sta attribDest+2

		ldx #$00
	!aloop:
		RunDMAJob(AttribJob)

		_add16(attribSource, src_stride, attribSource)
		_add16im(attribDest, LOGICAL_ROW_SIZE, attribDest)

		inx
		cpx #NUM_ROWS
		bne !aloop-

		rts 

	// ----------------------------
	TileJob:		.byte $0A 						// Request format is F018A
					.byte $80
	tileSrcBank:	.byte $00						// Source BANK
					.byte $81
	tileDestBank:	.byte $00						// Dest BANK

					.byte $00 						// No more options

					//byte 01
					.byte $00 						// Copy and last request
	tileLength:		.word $0000						// Size of Copy

					//byte 04
	tileSource:		.byte $00,$00,$00				// Source

					//byte 07
	tileDest:		.byte $00,$00,$00				// Destination & $ffff, [[Destination >> 16] & $0f]

					//byte 10
					.word $0000

	// ----------------------------
	AttribJob:		.byte $0A 						// Request format is F018A
					.byte $80
	attribSrcBank:	.byte $00						// Source BANK
					.byte $81
	attribDestBank:	.byte $00						// Dest BANK

					.byte $00 						// No more options

					// byte 01
					.byte $00 						// Copy and last request
	attribLength:	.word $0000						// Size of Copy

					//byte 04
	attribSource:	.byte $00,$00,$00				// Source

					//byte 07
	attribDest:		.byte $00,$00,$00				// Destination & $ffff, [[Destination >> 16] & $0f]

					//byte 10
					.word $0000
	}
}

// ------------------------------------------------------------
//
#import "mega65system.asm"

// ------------------------------------------------------------
// Fill the screen and color ram buffers with RRB data for the GOTOX columns
//
InitScreenColorRAM: {
	.var screenPtr = Tmp			// 32bit
	.var attribPtr = Tmp1			// 32bit
	.var gotoXmarker = Tmp2			// 8bit
	.var tmpChar = Tmp2+2			// 16bit

	_set32im(ScreenRam, screenPtr)
	_set32im(COLOR_RAM, attribPtr)

	ldy #$00

lineLoop:

	_set16im(Chars/64, tmpChar)

	// First layer uses GOTOX flag
	lda #$10
	sta gotoXmarker

	ldx #$00

layerLoop:

	ldz #$00

	// Screen byte 0 : GOTOX <pos
	lda #$00
	sta ((screenPtr)),z
	// Attrib byte 0 : GOTOX marker - Byte0bit4=GOTOXMarker
	lda gotoXmarker
	sta ((attribPtr)),z
	inz	

	// Screen byte 1 : GOTOX >pos
	lda #$00
	sta ((screenPtr)),z
	// Attrib byte 1 : GOTOX marker - Byte1
	lda #$00
	sta ((attribPtr)),z
	inz	

	// Second layer needs to be transparent
	lda gotoXmarker
	ora #$80
	sta gotoXmarker

	_add16im(tmpChar, 8, tmpChar)

	_add32im(screenPtr, LOGICAL_LAYER_SIZE, screenPtr)
	_add32im(attribPtr, LOGICAL_LAYER_SIZE, attribPtr)

	inx
	cpx #$02
	bne layerLoop

	// do for all rows
	iny	
	cpy #NUM_ROWS
	bne lineLoop

	rts
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
.segment Data "Chars"
.align 64
Chars:
	.import binary "./ncm_test_chr.bin"

.segment Data "Palettes"
Palette:
	.import binary "./ncm_test_pal.bin"

sintable:
	.fill 256, 84 + (sin((i/256) * PI * 2) * 84)
costable:
	.fill 256, 84 + (cos((i/256) * PI * 2) * 84)

// ------------------------------------------------------------
//
.segment Data "Map Char Data"

// Map Char Data for bottom layer
//
MapRam:
{
	.for(var r = 0;r < MAP_HEIGHT;r++) 
	{
		.for(var c = 0;c < MAP_WIDTH;c++) 
		{
			.var choffs = (Chars/64) + (((r&3)*2) + (c&1))
			//Char index
			.byte <choffs,>choffs
		}
	}
}

// Map Char Data for top layer
//
MapRam2:
{
	.for(var r = 0;r < MAP_HEIGHT;r++) 
	{
		.for(var c = 0;c < MAP_WIDTH;c++) 
		{
			.var choffs = (Chars/64) + (((r&3)*2) + (c&1)) + 8
			//Char index
			.byte <choffs,>choffs
		}
	}
}

// ------------------------------------------------------------
//
.segment Data "Map Attrib Data"

// Map Char Data for top layer
//
AttribRam:
{
	.for(var r = 0;r < MAP_HEIGHT;r++) 
	{
		.for(var c = 0;c < MAP_WIDTH;c++) 
		{
			// Byte0bit3 = NCM
			// Byte1bit0-3 = cycle colour 15 index
			.byte $08,(c/2)&$0f
		}
	}
}

// ------------------------------------------------------------
//
.segment ScreenRam "Screen RAM"
ScreenRam:
	.fill (LOGICAL_ROW_SIZE * NUM_ROWS), $00

