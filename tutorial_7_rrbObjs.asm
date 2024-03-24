// ------------------------------------------------------------
//
// Tutorial 7 - 8 way parallax scrolling with RRBObjs.
//
// Shows how to add RRBObjs on top of multiple RRB layers.
//
// Char and Attrib data are DMA'd into the screen RRB layout and the GOTOX position for 
// each row is set accordingly.
//
//
.file [name="tutorial_7_rrbObjs.prg", segments="Code,Data"]

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
.const SCREEN_WIDTH = 160

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

.const NUM_LAYERS = 2

// LOGICAL_OBJS_SIZE is the number of bytes reserved for objs on each row, at a minimum,
// one objs is a GOTOX + CHAR
//
.const LOGICAL_OBJS_SIZE = 2 * (4)

// LOGICAL_EOL_SIZE is the end of line marker, this consists of a GOTOX(SCREEN_WIDTH) + CHAR
// this end of line set are needed to ensure that all of the line is visible as the RRB
// system will only draw up to the position of the last character.
.const LOGICAL_EOL_SIZE = 2 * (2)

// LOGICAL_ROW_SIZE is the number of bytes the VIC-IV advances each row
//
.const LOGICAL_ROW_SIZE = (LOGICAL_LAYER_SIZE * NUM_LAYERS) + LOGICAL_OBJS_SIZE + LOGICAL_EOL_SIZE
.const LOGICAL_NUM_ROWS = NUM_ROWS

// ------------------------------------------------------------
//
.const MAP_WIDTH = (512 / 16)
.const MAP_HEIGHT = (SCREEN_HEIGHT / 8) * 2

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
	ScrollY1:		.byte $00,$00
	ScrollY2:		.byte $00,$00

	ShiftOffsetsL:	.byte $00, $00, $00, $00
	ShiftOffsetsH:	.byte $00, $00, $00, $00

	LayerMasks:		.byte $00,$00,$00,$00
	YShift:			.byte $00,$00,$00,$00

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

	// We only need to update EOL data once as it never changes
	//
	jsr UpdateLayerData.UpdateLayerEOL

	lda #$00
	sta $d020
	lda #$00
	sta $d021

	_set16im(0, ScrollX1)
	_set16im(0, ScrollX2)

	_set16im(0, ScrollY1)
	_set16im(0, ScrollY2)

	// Main loop
mainloop:
	// Wait for (H400) rasterline $07
!:	lda $d053
	and #$07
	cmp System.BotBorder+1
	bne !-
    lda System.BotBorder+0
	cmp $d052 
    bne !-
!:	cmp $d052 
    beq !-

	lda #$04
    sta $d020

	// Layer1 : Calculate how much to shift the layer row off the left size	
	ldx #$00
	lda ScrollX1
	jsr UpdateShiftAmount
	ldx #$01
	lda ScrollX1
	jsr UpdateShiftAmount

	// Layer2 : Calculate how much to shift the layer row off the left size	
	ldx #$02
	lda ScrollX2
	jsr UpdateShiftAmount
	ldx #$03
	lda ScrollX2
	jsr UpdateShiftAmount

	// Update the GOTOX position for all layers using the offsets calculated above
	jsr UpdateLayerPositions

	// Update the char / attrib data using DMA
	jsr UpdateLayerData.UpdateLayer1
	jsr UpdateLayerData.UpdateLayer2
	// jsr UpdateLayerData.UpdateLayer3
	// jsr UpdateLayerData.UpdateLayer4

	// Update RRBObjs using DMA
	jsr UpdateLayerData.UpdateLayerObjs

	lda #$0d
    sta $d020

	inc FrameCount

	// Do some sin/cos based scrolling for the 2 layers
	ldx FrameCount
	lda sintable,x
	sta ScrollX1
	sta ScrollY2

	lda costable,x
	sta ScrollX2
	sta ScrollY1

	// Clear the work Obj ram using DMA
	jsr ClearWorkObjs

	// Add Objs into the work ram here
	//
	jsr AddObj

	lda #$00
	sta $d020


	jmp mainloop

}

// ------------------------------------------------------------
//
AddObj:
{
	.var charPtr = Tmp				// 16bit
	.var attribPtr = Tmp+2			// 16bit

	_set32im(ObjWorkChars, charPtr)
	_set32im(ObjWorkAttrib, attribPtr)

	.var choffs = (Sprites/64) + 1

	ldz #$00
	
	// GOTOX
	ldx FrameCount
	lda costable,x
	sta (charPtr),z
	lda #$90
	sta (attribPtr),z
	inz
	lda #$00
	sta (charPtr),z
	lda #$00
	sta (attribPtr),z
	inz

	// Char
	lda #<choffs
	sta (charPtr),z
	lda #$08
	sta (attribPtr),z
	inz	
	lda #>choffs
	sta (charPtr),z
	lda #$1f
	sta (attribPtr),z
	inz	

	_set32im(ObjWorkChars + LOGICAL_OBJS_SIZE, charPtr)
	_set32im(ObjWorkAttrib + LOGICAL_OBJS_SIZE, attribPtr)

	.var choffs2 = (Sprites/64) + 2

	ldz #$00
	
	// GOTOX
	ldx FrameCount
	lda costable,x
	sta (charPtr),z
	lda #$90
	sta (attribPtr),z
	inz
	lda #$00
	sta (charPtr),z
	lda #$00
	sta (attribPtr),z
	inz

	// Char
	lda #<choffs2
	sta (charPtr),z
	lda #$08
	sta (attribPtr),z
	inz	
	lda #>choffs2
	sta (charPtr),z
	lda #$1f
	sta (attribPtr),z
	inz	

	rts
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
//shiftMasks: .byte $ff,$fe,$fc,$f8,$f0,$e0,$c0,$80
shiftMasks: .byte %11111111,%01111111,%00111111,%00011111,%00001111,%00000111,%00000011,%00000001,%00000000

UpdateLayerPositions:
{
	.var charLayerPtr = Tmp			// 32bit
	.var charRowPtr = Tmp1			// 32bit

	.var attribLayerPtr = Tmp2		// 32bit
	.var attribRowPtr = Tmp3		// 32bit

	.var gotoXmarker = Tmp4			// 8bit

	// Start layerPtr at top left GOTOX token
	_set32im(ScreenRam, charLayerPtr)
	_set32im(COLOR_RAM, attribLayerPtr)

	// set GotoX info
	lda #$18
	sta gotoXmarker

	// Parallax layer 1 (layers 0 & 1)
	lda ScrollY1
	and #$07
	sta YShift+0
	tax
	lda shiftMasks,x
	sta LayerMasks+0
	eor #$ff
	sta LayerMasks+1

	// Parallax layer 2 (layers 2 & 3)
	lda ScrollY2
	and #$07
	sta YShift+2
	tax
	lda shiftMasks,x
	sta LayerMasks+2
	eor #$ff
	sta LayerMasks+3

	// shift yshift left 5 times
	lda YShift+0
	asl	
	asl
	asl	
	asl
	asl
	sta YShift+0
	sta YShift+1

	// shift yshift left 5 times
	lda YShift+2
	asl	
	asl
	asl	
	asl
	asl
	sta YShift+2
	sta YShift+3

	// Update all layers
	ldx #$00

layerLoop:

	// Copy layerPtr to rowPtr
	_set32(charLayerPtr, charRowPtr)
	_set32(attribLayerPtr, attribRowPtr)

	// Update GOTOX position for each row in this layer
	ldy #$00

rowLoop:

	ldz #$00
	lda ShiftOffsetsL,x		// Update Byte0 of layer row
	sta ((charRowPtr)),z
	lda gotoXmarker
	sta ((attribRowPtr)),z
	inz
	lda YShift,x			// Get (FCM char data Y offset)
	ora ShiftOffsetsH,x		// Update Byte1 of layer row
	sta ((charRowPtr)),z
	lda LayerMasks,x
	sta ((attribRowPtr)),z

	// Advance row pointers to the next logical row
	_add32im(charRowPtr, LOGICAL_ROW_SIZE, charRowPtr)
	_add32im(attribRowPtr, LOGICAL_ROW_SIZE, attribRowPtr)
	
	iny	
	cpy #LOGICAL_NUM_ROWS
	bne rowLoop

	// Advance layer pointer to the next logical layer
	_add32im(charLayerPtr, LOGICAL_LAYER_SIZE, charLayerPtr)
	_add32im(attribLayerPtr, LOGICAL_LAYER_SIZE, attribLayerPtr)

	lda gotoXmarker
	ora #$80
	sta gotoXmarker

	inx
	cpx #NUM_LAYERS
	lbne layerLoop

	rts
}

// ------------------------------------------------------------
//
ClearWorkObjs: {
// 	.var chr_ptr = Tmp
// 	.var attrib_ptr = Tmp1

// 	// Clear the RRBIndex list
// 	_set32im(RRBTileBuffer, chr_ptr)
// 	_set32im(RRBAttribBuffer, attrib_ptr)

// 	ldx #0
// !:		
// 	// Set the RRB count with the number of bytes available on this row
// 	lda #LayerRRB.DataSize
// 	sta RRBCount,x

// 	// Set the RRB ptr to the beginning of RRB data for this row
// 	lda chr_ptr+0
// 	sta RRBTileRowTableLo,x
// 	lda chr_ptr+1
// 	sta RRBTileRowTableHi,x

// 	lda attrib_ptr+0
// 	sta RRBAttribRowTableLo,x
// 	lda attrib_ptr+1
// 	sta RRBAttribRowTableHi,x

// 	// Advance to the next row
// 	_add16im(chr_ptr, LayerRRB.DataSize, chr_ptr)
// 	_add16im(attrib_ptr, LayerRRB.DataSize, attrib_ptr)

// 	inx
// 	cpx #NUM_ROWS
// 	bne !-

	// Clear the RRB characters using DMA
	RunDMAJob(Job)

	rts 
Job:
	DMAHeader(ClearObjChar>>20, ObjWorkChars>>20)
	.for(var r=0; r<NUM_ROWS; r++) {
		// Tile
		DMACopyJob(
			ClearObjChar, 
			ObjWorkChars + (r * LOGICAL_OBJS_SIZE),
			LOGICAL_OBJS_SIZE,
			true, false)
		// Atrib
		DMACopyJob(
			ClearObjAttrib,
			ObjWorkAttrib + (r * LOGICAL_OBJS_SIZE),
			LOGICAL_OBJS_SIZE,
			(r!=(NUM_ROWS-1)), false)
	}
 .print ("RRBClear DMAjob = " + (* - Job))
}	



// ------------------------------------------------------------
// To update the char / attrib data for the scrolling layers we need to DMA
// data from the Map into the screen, this is done as a DMA for each row,
// one for chars and one for attribs.
//
colTabL: 
	.fill 32, <(MAP_LOGICAL_SIZE * i)
colTabH: 
	.fill 32, >(MAP_LOGICAL_SIZE * i)

UpdateLayerData: {
	.var src_tile_ptr = Tmp			// 32bit
	.var src_attrib_ptr = Tmp1		// 32bit

	.var dst_offset = Tmp2			// 16bit
	.var copy_length = Tmp2+2		// 16bit

	.var src_offset = Tmp3			// 16bit
	.var src_stride = Tmp3+2		// 16bit

	.var scrollY = Tmp4				// 16bit

	UpdateLayer1: {
		_set32im(MapRam, src_tile_ptr)
		_set32im(AttribRam, src_attrib_ptr)

		_set16im(MAP_LOGICAL_SIZE, src_stride)

		_set16(ScrollY1, scrollY)
		lsr scrollY+1
		ror scrollY+0
		lsr scrollY+1
		ror scrollY+0
		lsr scrollY+1
		ror scrollY+0

		ldx scrollY+0
		clc
		lda src_tile_ptr+0
		adc colTabL,x
		sta src_tile_ptr+0
		lda src_tile_ptr+1
		adc colTabH,x
		sta src_tile_ptr+1

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
		_set32im(MapRam2 + MAP_LOGICAL_SIZE, src_tile_ptr)
		_set32im(AttribRam, src_attrib_ptr)

		_set16im(MAP_LOGICAL_SIZE, src_stride)

		_set16(ScrollY1, scrollY)
		lsr scrollY+1
		ror scrollY+0
		lsr scrollY+1
		ror scrollY+0
		lsr scrollY+1
		ror scrollY+0

		ldx scrollY+0
		clc
		lda src_tile_ptr+0
		adc colTabL,x
		sta src_tile_ptr+0
		lda src_tile_ptr+1
		adc colTabH,x
		sta src_tile_ptr+1

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

		// Copy into char after GOTOX on the second layer
		_set16im(2 + LOGICAL_LAYER_SIZE, dst_offset)

		_set16im(CHARS_WIDE * 2, copy_length)

		jsr CopyLayerChunks

		rts
	}

	UpdateLayer3: {
		_set32im(MapRam3, src_tile_ptr)
		_set32im(AttribRam, src_attrib_ptr)

		_set16im(MAP_LOGICAL_SIZE, src_stride)

		_set16(ScrollY2, scrollY)
		lsr scrollY+1
		ror scrollY+0
		lsr scrollY+1
		ror scrollY+0
		lsr scrollY+1
		ror scrollY+0

		ldx scrollY+0
		clc
		lda src_tile_ptr+0
		adc colTabL,x
		sta src_tile_ptr+0
		lda src_tile_ptr+1
		adc colTabH,x
		sta src_tile_ptr+1

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
		_set16im(2 + (LOGICAL_LAYER_SIZE * 2), dst_offset)

		_set16im(CHARS_WIDE * 2, copy_length)

		jsr CopyLayerChunks

		rts
	}

	UpdateLayer4: {
		_set32im(MapRam4 + MAP_LOGICAL_SIZE, src_tile_ptr)
		_set32im(AttribRam, src_attrib_ptr)

		_set16im(MAP_LOGICAL_SIZE, src_stride)

		_set16(ScrollY2, scrollY)
		lsr scrollY+1
		ror scrollY+0
		lsr scrollY+1
		ror scrollY+0
		lsr scrollY+1
		ror scrollY+0
		ldx scrollY+0
		clc
		lda src_tile_ptr+0
		adc colTabL,x
		sta src_tile_ptr+0
		lda src_tile_ptr+1
		adc colTabH,x
		sta src_tile_ptr+1

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
		_set16im(2 + (LOGICAL_LAYER_SIZE * 3), dst_offset)

		_set16im(CHARS_WIDE * 2, copy_length)

		jsr CopyLayerChunks

		rts
	}

	UpdateLayerObjs: {
		_set32im(ObjWorkChars, src_tile_ptr)
		_set32im(ObjWorkAttrib, src_attrib_ptr)

		_set16im(LOGICAL_OBJS_SIZE, src_stride)

		_set16im(0, src_offset)

		// Copy into Obj layer
		_set16im(LOGICAL_LAYER_SIZE * NUM_LAYERS, dst_offset)

		_set16im(LOGICAL_OBJS_SIZE, copy_length)

		jsr CopyLayerChunks

		rts
	}

	UpdateLayerEOL: {
		_set32im(EOLChar, src_tile_ptr)
		_set32im(EOLAttrib, src_attrib_ptr)

		// We are copying the same data into each row so don't advance the src ptrs
		_set16im(0, src_stride)

		_set16im(0, src_offset)

		// Copy into Obj layer
		_set16im((LOGICAL_LAYER_SIZE * NUM_LAYERS) + LOGICAL_OBJS_SIZE, dst_offset)

		_set16im(LOGICAL_EOL_SIZE, copy_length)

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

		lda Palette + $030,x 	// sprite
		sta $d110,x
		lda Palette + $040,x 
		sta $d210,x
		lda Palette + $050,x 
		sta $d310,x

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

.segment Data "Sprites"
.align 64
Sprites:
	.import binary "./ncm_sprite_chr.bin"

.segment Data "Palettes"
Palette:
	.import binary "./ncm_test_pal.bin"
	.import binary "./ncm_sprite_pal.bin"

sintable:
	.fill 256, 84 + (sin((i/256) * PI * 2) * 84)
costable:
	.fill 256, 84 + (cos((i/256) * PI * 2) * 84)

// ------------------------------------------------------------
//
.segment Data "RRB Clear Data"
ClearObjChar:
	.for(var c = 0;c < LOGICAL_OBJS_SIZE/2;c++) 
	{
		.byte <SCREEN_WIDTH,>SCREEN_WIDTH
	}

ClearObjAttrib:
	.for(var c = 0;c < LOGICAL_OBJS_SIZE/2;c++) 
	{
		.byte $90,$00
	}

// ------------------------------------------------------------
//
.segment Data "RRB EOL Data"
EOLChar:
	.byte <SCREEN_WIDTH,>SCREEN_WIDTH
	.byte $00,$00

EOLAttrib:
	.byte $90,$00
	.byte $08,$0f

// ------------------------------------------------------------
//
.segment Data "Map Char Data"

// Map Char Data for top layer
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

MapRam2:
{
	.for(var r = 0;r < MAP_HEIGHT;r++) 
	{
		.for(var c = 0;c < MAP_WIDTH;c++) 
		{
			.var choffs = ((Chars/64) + (((r&3)*2) + (c&1))) - 1
			//Char index
			.byte <choffs,>choffs
		}
	}
}

MapRam3:
{
	.for(var r = 0;r < MAP_HEIGHT;r++) 
	{
		.for(var c = 0;c < MAP_WIDTH;c++) 
		{
			.var choffs = (Chars/64) + (((r&3)*2) + (c&1) + 8)
			//Char index
			.byte <choffs,>choffs
		}
	}
}

MapRam4:
{
	.for(var r = 0;r < MAP_HEIGHT;r++) 
	{
		.for(var c = 0;c < MAP_WIDTH;c++) 
		{
			.var choffs = ((Chars/64) + (((r&3)*2) + (c&1)) + 8) - 1
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
.segment BSS "Obj Work RAM"
ObjWorkChars:
	.fill (LOGICAL_OBJS_SIZE * NUM_ROWS), $00
ObjWorkAttrib:
	.fill (LOGICAL_OBJS_SIZE * NUM_ROWS), $00

// ------------------------------------------------------------
//
.segment ScreenRam "Screen RAM"
ScreenRam:
	.fill (LOGICAL_ROW_SIZE * NUM_ROWS), $00

