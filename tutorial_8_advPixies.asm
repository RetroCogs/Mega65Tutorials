// ------------------------------------------------------------
//
// Tutorial 8 - 8 way parallax scrolling with Pixies.
//
// Shows how to add Pixies on top of multiple RRB layers.
//
// Tile and Attrib data are DMA'd into the screen RRB layout and the GOTOX position for 
// each row is set accordingly.
//
//
.file [name="tutorial_8_advPixies.prg", segments="Code,Data"]

// Color RAM is at a fixed base address
//
.const COLOR_RAM = $ff80000

// ------------------------------------------------------------
//
.segmentdef Zeropage [start=$02, min=$02, max=$fb, virtual]
.segmentdef Code [start=$2001, max=$cfff]
.segmentdef Data [start=$4000, max=$cfff]
.segmentdef BSS [start=$e000, max=$f400, virtual]

.segmentdef MappedPixieWorkRam [start=$4000, max=$7fff, virtual]

.segmentdef ScreenRam [start=$50000, virtual]
.segmentdef PixieWorkRam [start=$54000, virtual]

.cpu _45gs02				

// ------------------------------------------------------------
// Defines to describe the screen size
//
// If you use H320 then SCREEN_WIDTH much be <= 360, otherwise <= 720
#define H320
.const SCREEN_WIDTH = 320

// If you use V200 then SCREEN_HEIGHT much be <= 240
#define V200
.const SCREEN_HEIGHT = 200

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

.const NUM_LAYERS = 4

// LOGICAL_PIXIE_SIZE is the number of bytes reserved for pixies on each row, at a minimum,
// one pixie is a GOTOX + CHAR (2 words)
//
.const NUM_PIXIEWORDS = 160

.const LOGICAL_PIXIE_SIZE = 2 * (NUM_PIXIEWORDS)

// LOGICAL_EOL_SIZE is the end of line marker, this consists of a GOTOX(SCREEN_WIDTH) + CHAR
// this end of line set are needed to ensure that all of the line is visible as the RRB
// system will only draw up to the position of the last character.
.const LOGICAL_EOL_SIZE = 2 * (2)

// LOGICAL_ROW_SIZE is the number of bytes the VIC-IV advances each row
//
.const LOGICAL_ROW_SIZE = (LOGICAL_LAYER_SIZE * NUM_LAYERS) + LOGICAL_PIXIE_SIZE + LOGICAL_EOL_SIZE
.const LOGICAL_NUM_ROWS = NUM_ROWS

 .print ("LOGICAL_ROW_SIZE = " + LOGICAL_ROW_SIZE)

// ------------------------------------------------------------
//
.const MAP_WIDTH = (512 / 16)
.const MAP_HEIGHT = (SCREEN_HEIGHT / 8) * 2

// MAP_LOGICAL_SIZE is the number of bytes each row takes in the map / attrib data
//
.const MAP_LOGICAL_SIZE = MAP_WIDTH * 2

// ------------------------------------------------------------
//
.const NUM_OBJS1 = 64
.const NUM_OBJS2 = 64
.const NUM_OBJS3 = 64

// ------------------------------------------------------------
//
.segment Zeropage "Main zeropage"
	Tmp:			.word $0000,$0000
	Tmp1:			.word $0000,$0000
	Tmp2:			.word $0000,$0000
	Tmp3:			.word $0000,$0000
	Tmp4:			.word $0000,$0000

	FrameCount:		.byte $00

	AnimCount:		.byte $00

	ScrollX1:		.byte $00,$00
	ScrollX2:		.byte $00,$00
	ScrollY1:		.byte $00,$00
	ScrollY2:		.byte $00,$00

	ShiftOffsetsL:	.byte $00, $00, $00, $00
	ShiftOffsetsH:	.byte $00, $00, $00, $00

	LayerMasks:		.byte $00,$00,$00,$00
	YShift:			.byte $00,$00,$00,$00

	ObjPosX:		.byte $00,$00
	ObjPosY:		.byte $00,$00
    ObjChar:        .byte $00,$00

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

    jsr CopyMap3to4

	// Main loop
mainloop:
	// Wait for (H400) rasterline $07
!:	lda $d053
	and #$07
	cmp.zp System.BotBorder+1
	bne !-
    lda.zp System.BotBorder+0
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

	// Update the tile / attrib data using DMA
	jsr UpdateLayerData.UpdateLayer1
	jsr UpdateLayerData.UpdateLayer2
	jsr UpdateLayerData.UpdateLayer3
	jsr UpdateLayerData.UpdateLayer4

	// Update Pixie data using DMA
	jsr UpdateLayerData.UpdateLayerPixies

	lda #$08
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

	// Clear the work Pixie ram using DMA
	jsr ClearWorkPixies

	inc AnimCount

	lda #$00
	sta ObjPosY+1

    // Map PixieWorkRam (at $54000) into MappedPixieWorkRam (at $4000)
    mapLo(PixieWorkTiles, MappedPixieWorkTiles, $0c)
    mapHi(PixieWorkTiles+$4000, MappedPixieWorkTiles+$4000, $03)
	map
	eom

	_set16im((Sprites/64), ObjChar)			// Start charIndx with first pixie char

	// Add Objs into the work ram here
	//
	ldx #$00
!:
	clc
	lda Objs1PosXLo,x
	adc Objs1VelX,x
	sta Objs1PosXLo,x

	clc
	lda Objs1PosYLo,x
	adc Objs1VelY,x
	sta Objs1PosYLo,x

	clc
	lda Objs1PosXLo,x
	adc #32
	sta ObjPosX+0
	lda #$00
	adc #$00
	sta ObjPosX+1

	lda Objs1PosYLo,x
	sta ObjPosY+0

	phx
	jsr AddObj
	plx

	inx
	cpx #NUM_OBJS1
	bne !-

	_set16im((Sprites/64)+2, ObjChar)			// Start charIndx with first pixie char

	// Add Objs into the work ram here
	//
	ldx #$00
!:
	clc
	lda Objs2PosXLo,x
	adc Objs2VelX,x
	sta Objs2PosXLo,x

	clc
	lda Objs2PosYLo,x
	adc Objs2VelY,x
	sta Objs2PosYLo,x

	clc
	lda Objs2PosXLo,x
	adc #32
	sta ObjPosX+0
	lda #$00
	adc #$00
	sta ObjPosX+1

	lda Objs2PosYLo,x
	sta ObjPosY+0

	phx
	jsr AddObj
	plx

	inx
	cpx #NUM_OBJS2
	bne !-

	_set16im((Sprites/64), ObjChar)			// Start charIndx with first pixie char

	// Add Objs into the work ram here
	//
	ldx #$00
!:
	clc
	lda Objs3PosXLo,x
	adc Objs3VelX,x
	sta Objs3PosXLo,x

	clc
	lda Objs3PosYLo,x
	adc Objs3VelY,x
	sta Objs3PosYLo,x

	clc
	lda Objs3PosXLo,x
	adc #32
	sta ObjPosX+0
	lda #$00
	adc #$00
	sta ObjPosX+1

	lda Objs3PosYLo,x
	sta ObjPosY+0

	phx
	jsr AddObj
	plx

	inx
	cpx #NUM_OBJS3
	bne !-

    unmapMemory()

	lda #$00
	sta $d020


	jmp mainloop

}

// ------------------------------------------------------------
//
yShiftTable:	.byte 0<<5,7<<5,6<<5,5<<5,4<<5,3<<5,2<<5,1<<5
yMaskTable:		.byte %11111111,%11111110,%11111100,%11111000,%11110000,%11100000,%11000000,%10000000

AddObj:
{
	.var tilePtr = Tmp				// 16bit
	.var attribPtr = Tmp+2			// 16bit

	.var charIndx = Tmp1+0			// 16bit
	.var yShift = Tmp1+2			// 8bit

	.var gotoXmask = Tmp2			// 8bit

	_set16(ObjChar, charIndx)			// Start charIndx with first pixie char

	lda ObjPosY+0						// Find sub row y offset (0 - 7)
	and #$07
	tay	

	lda yMaskTable,y					// grab the rowMask value
	sta gotoXmask

	lda yShiftTable,y					// grab the yShift value 
	sta yShift

	beq !+								// if (yShift != 0) charIndx--

    dew charIndx

!:

	// Calculate which row to add pixie data to, put this in X,
    // we use this to index the row tile / attrib ptrs
 	// 
	lda ObjPosY+0
	lsr	
	lsr	
	lsr	
	dec 
	dec 
	tax									// move yRow into X reg
	bmi middleRow
	cpx #NUM_ROWS
	lbcs done

	// Top character, this uses the first mask from the tables above,
    // grab tile and attrib ptr for this row and advance by the 4 bytes
    // that we will write per row.
	//
	clc                                 // grab and advance tilePtr
	lda PixieRowScreenPtrLo,x
	sta tilePtr+0
	adc #$04
	sta PixieRowScreenPtrLo,x
	lda PixieRowScreenPtrHi,x
	sta tilePtr+1
	adc #$00
	sta PixieRowScreenPtrHi,x
	clc                                 // grab and advance attribPtr
	lda PixieRowAttribPtrLo,x
	sta attribPtr+0
	adc #$04
	sta PixieRowAttribPtrLo,x
	lda PixieRowAttribPtrHi,x
	sta attribPtr+1
	adc #$00
	sta PixieRowAttribPtrHi,x

	// GOTOX
	ldz #$00
	lda ObjPosX+0						// tile = <xpos,>xpos | yShift
	sta (tilePtr),z
	lda #$98							// attrib = $98 (transparent+gotox+rowmask), gotoXmask
	sta (attribPtr),z
	inz
	lda ObjPosX+1
	and #$03
	ora yShift
	sta (tilePtr),z
	lda gotoXmask
	sta (attribPtr),z
	inz

	// Char
	lda charIndx+0
	sta (tilePtr),z
	lda #$08
	sta (attribPtr),z
	inz	
	lda charIndx+1
	sta (tilePtr),z
	lda #$1f
	sta (attribPtr),z

middleRow:
	// Advance to next row and charIndx
    inw charIndx
	inx
	bmi bottomRow
	cpx #NUM_ROWS
	lbcs done

	// Middle character, yShift is the same as first char but full character is drawn so disable rowmask,
    // grab tile and attrib ptr for this row and advance by the 4 bytes
    // that we will write per row.
	//
	clc                                 // grab and advance tilePtr
	lda PixieRowScreenPtrLo,x
	sta tilePtr+0
	adc #$04
	sta PixieRowScreenPtrLo,x
	lda PixieRowScreenPtrHi,x
	sta tilePtr+1
	adc #$00
	sta PixieRowScreenPtrHi,x
	clc                                 // grab and advance attribPtr
	lda PixieRowAttribPtrLo,x
	sta attribPtr+0
	adc #$04
	sta PixieRowAttribPtrLo,x
	lda PixieRowAttribPtrHi,x
	sta attribPtr+1
	adc #$00
	sta PixieRowAttribPtrHi,x	

	// GOTOX
	ldz #$00
	lda ObjPosX+0						// tile = <xpos,>xpos | yShift
	sta (tilePtr),z
	lda #$90							// attrib = $98 (transparent+gotox), $00
	sta (attribPtr),z
	inz
	lda ObjPosX+1
	and #$03
	ora yShift
	sta (tilePtr),z
	lda #$ff
	sta (attribPtr),z
	inz

	// Char
	lda charIndx+0
	sta (tilePtr),z
	lda #$08
	sta (attribPtr),z
	inz	
	lda charIndx+1
	sta (tilePtr),z
	lda #$1f
	sta (attribPtr),z

bottomRow:
	// If we have a yShift of 0 we only need to add to 2 rows, skip the last row!
	//
	lda yShift
	beq done

	// Advance to next row and charIndx
    inw charIndx
	inx
	bmi done
	cpx #NUM_ROWS
	lbcs done

	// Bottom character, yShift is the same as first char but flip the bits of the gotoXmask,
    // grab tile and attrib ptr for this row and advance by the 4 bytes
    // that we will write per row.
	//
	clc                                 // grab and advance tilePtr
	lda PixieRowScreenPtrLo,x
	sta tilePtr+0
	adc #$04
	sta PixieRowScreenPtrLo,x
	lda PixieRowScreenPtrHi,x
	sta tilePtr+1
	adc #$00
	sta PixieRowScreenPtrHi,x
	clc                                 // grab and advance tilePtr
	lda PixieRowAttribPtrLo,x
	sta attribPtr+0
	adc #$04
	sta PixieRowAttribPtrLo,x
	lda PixieRowAttribPtrHi,x
	sta attribPtr+1
	adc #$00
	sta PixieRowAttribPtrHi,x

	lda gotoXmask
	eor #$ff
	sta gotoXmask

	// GOTOX
	ldz #$00
	lda ObjPosX+0						// tile = <xpos,>xpos | yShift	
	sta (tilePtr),z
	lda #$98							// attrib = $98 (transparent+gotox+rowmask), gotoXmask
	sta (attribPtr),z
	inz
	lda ObjPosX+1
	and #$03
	ora yShift
	sta (tilePtr),z
	lda gotoXmask
	sta (attribPtr),z
	inz

	// Char
	lda charIndx+0
	sta (tilePtr),z
	lda #$08
	sta (attribPtr),z
	inz	
	lda charIndx+1
	sta (tilePtr),z
	lda #$1f
	sta (attribPtr),z

done:

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
	.var tileLayerPtr = Tmp			// 32bit
	.var tileRowPtr = Tmp1			// 32bit

	.var attribLayerPtr = Tmp2		// 32bit
	.var attribRowPtr = Tmp3		// 32bit

	.var gotoXmarker = Tmp4			// 8bit

	// Start layerPtr at top left GOTOX token
	_set32im(ScreenRam, tileLayerPtr)
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
	_set32(tileLayerPtr, tileRowPtr)
	_set32(attribLayerPtr, attribRowPtr)

	// Update GOTOX position for each row in this layer
	ldy #$00

rowLoop:

	ldz #$00
	lda ShiftOffsetsL,x		// Update Byte0 of layer row
	sta ((tileRowPtr)),z
	lda gotoXmarker
	sta ((attribRowPtr)),z
	inz
	lda YShift,x			// Get (FCM char data Y offset)
	ora ShiftOffsetsH,x		// Update Byte1 of layer row
	sta ((tileRowPtr)),z
	lda LayerMasks,x
	sta ((attribRowPtr)),z

	// Advance row pointers to the next logical row
	_add32im(tileRowPtr, LOGICAL_ROW_SIZE, tileRowPtr)
	_add32im(attribRowPtr, LOGICAL_ROW_SIZE, attribRowPtr)
	
	iny	
	cpy #LOGICAL_NUM_ROWS
	bne rowLoop

	// Advance layer pointer to the next logical layer
	_add32im(tileLayerPtr, LOGICAL_LAYER_SIZE, tileLayerPtr)
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
ClearWorkPixies: {
	.var rowScreenPtr = Tmp		// 16bit
	.var rowAttribPtr = Tmp+2	// 16bit

	_set16im(PixieWorkTiles, rowScreenPtr)
	_set16im(PixieWorkAttrib, rowAttribPtr)

	// Clear the RRBIndex list
	ldx #0
!:		
	lda rowScreenPtr+0
	sta PixieRowScreenPtrLo,x
	lda rowScreenPtr+1
	sta PixieRowScreenPtrHi,x

	lda rowAttribPtr+0
	sta PixieRowAttribPtrLo,x
	lda rowAttribPtr+1
	sta PixieRowAttribPtrHi,x

	_add16im(rowScreenPtr, LOGICAL_PIXIE_SIZE, rowScreenPtr)
	_add16im(rowAttribPtr, LOGICAL_PIXIE_SIZE, rowAttribPtr)
	
	inx
	cpx #NUM_ROWS
	bne !-

	// Clear the working pixie data using DMA
	RunDMAJob(Job)

	rts 
Job:
	DMAHeader(ClearPixieTile>>20, PixieWorkTiles>>20)
	.for(var r=0; r<NUM_ROWS; r++) {
		// Tile
		DMACopyJob(
			ClearPixieTile, 
			PixieWorkTiles + (r * LOGICAL_PIXIE_SIZE),
			LOGICAL_PIXIE_SIZE,
			true, false)
		// Atrib
		DMACopyJob(
			ClearPixieAttrib,
			PixieWorkAttrib + (r * LOGICAL_PIXIE_SIZE),
			LOGICAL_PIXIE_SIZE,
			(r!=(NUM_ROWS-1)), false)
	}
 .print ("RRBClear DMAjob = " + (* - Job))
}	



// ------------------------------------------------------------
// To update the tile / attrib data for the scrolling layers we need to DMA
// data from the Map into the screen, this is done as a DMA for each row,
// one for tiles and one for attribs.
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

		// Copy into tile after GOTOX
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

		// Copy into tile after GOTOX on the second layer
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

		// Copy into tile after GOTOX on the second layer
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

		// Copy into tile after GOTOX on the second layer
		_set16im(2 + (LOGICAL_LAYER_SIZE * 3), dst_offset)

		_set16im(CHARS_WIDE * 2, copy_length)

		jsr CopyLayerChunks

		rts
	}

	UpdateLayerPixies: {
		_set32im(PixieWorkTiles, src_tile_ptr)
		_set32im(PixieWorkAttrib, src_attrib_ptr)

		_set16im(LOGICAL_PIXIE_SIZE, src_stride)

		_set16im(0, src_offset)

		// Copy into Pixie layer
		_set16im(LOGICAL_LAYER_SIZE * NUM_LAYERS, dst_offset)

		_set16im(LOGICAL_PIXIE_SIZE, copy_length)

		jsr CopyLayerChunks

		rts
	}

	UpdateLayerEOL: {
		_set32im(EOLTile, src_tile_ptr)
		_set32im(EOLAttrib, src_attrib_ptr)

		// We are copying the same data into each row so don't advance the src ptrs
		_set16im(0, src_stride)

		_set16im(0, src_offset)

		// Copy into EOL layer
		_set16im((LOGICAL_LAYER_SIZE * NUM_LAYERS) + LOGICAL_PIXIE_SIZE, dst_offset)

		_set16im(LOGICAL_EOL_SIZE, copy_length)

		jsr CopyLayerChunks

		rts
	}

	// Loop for each row in both tiles and attribs and DMA one screen wide piece of data
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

CopyMap3to4: {
    .var mapSrcPtr = Tmp       // 16bit
    .var mapDstPtr = Tmp+2     // 16bit

    _set16im(MapRam3, mapSrcPtr)
    _set16im(MapRam4, mapDstPtr)

    ldz #$00
oloop:

    ldx #$00
iloop:

    ldy #$00

    sec
    lda (mapSrcPtr),y
    sbc #$01
    sta (mapDstPtr),y
    iny
    lda (mapSrcPtr),y
    sbc #$00
    sta (mapDstPtr),y

    _add16im(mapSrcPtr, 2, mapSrcPtr)
    _add16im(mapDstPtr, 2, mapDstPtr)

    inx
    cpx #MAP_WIDTH
    bne iloop

    inz
    cpz #MAP_HEIGHT
    bne oloop

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

ClearChar:
	.fill 64, 0

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
.segment Code "RRB Clear Data"
ClearPixieTile:
	.for(var c = 0;c < LOGICAL_PIXIE_SIZE/2;c++) 
	{
		.byte <SCREEN_WIDTH,>SCREEN_WIDTH
	}

ClearPixieAttrib:
	.for(var c = 0;c < LOGICAL_PIXIE_SIZE/2;c++) 
	{
		.byte $90,$00
	}

// ------------------------------------------------------------
//
.segment Code "RRB EOL Data"
EOLTile:
	.byte <SCREEN_WIDTH,>SCREEN_WIDTH
	.byte $00,$00

EOLAttrib:
	.byte $90,$00
	.byte $08,$0f

// ------------------------------------------------------------
//
.segment Data "Map Tile Data"


// Map Tile Data for bottom layer
//
MapRam:
{
	.for(var r = 0;r < MAP_HEIGHT;r++) 
	{
		.for(var c = 0;c < MAP_WIDTH;c++) 
		{
			.var choffs = (Chars/64) + (((r&7)*2) + (c&1))
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
			.var choffs = ((Chars/64) + (((r&7)*2) + (c&1))) - 1
			//Char index
			.byte <choffs,>choffs
		}
	}
}

// Map Tile Data for top layer
//
MapRam3:
{
	.for(var r = 0;r < MAP_HEIGHT;r++) 
	{
		.for(var c = 0;c < MAP_WIDTH;c++) 
		{
			.var choffs = (Chars/64) + (((r&7)*2) + (c&1) + 16)
            .if (random() < 0.5)
                .eval choffs = (ClearChar/64)
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
			.var choffs = ((Chars/64) + (((r&7)*2) + (c&1) + 16)) - 1
			//Char index
			.byte <choffs,>choffs
		}
	}
}

// ------------------------------------------------------------
//
.segment Data "Map Attrib Data"

// Map Attrib Data for all layers because they are all using the same palette index
//
AttribRam:
{
	.for(var r = 0;r < MAP_HEIGHT;r++) 
	{
		.for(var c = 0;c < MAP_WIDTH;c++) 
		{
			// Byte0bit3 = NCM
			// Byte1bit0-3 = cycle colour 15 index
			.byte $08,$0f
		}
	}
}

// ------------------------------------------------------------
//
.segment Code "Obj Data"

Objs1PosXLo:
	.fill NUM_OBJS1, i * -28
Objs1PosYLo:
	.fill NUM_OBJS1, (i * 10)
Objs1VelX:
	.fill NUM_OBJS1, random() > 0.5 ? -1 : 1
Objs1VelY:
	.fill NUM_OBJS1, 1

Objs2PosXLo:
	.fill NUM_OBJS2, i * 28
Objs2PosYLo:
	.fill NUM_OBJS2, (i * 10)
Objs2VelX:
	.fill NUM_OBJS2, random() > 0.5 ? -1 : 1
Objs2VelY:
	.fill NUM_OBJS2, -1

Objs3PosXLo:
	.fill NUM_OBJS2, i * 17
Objs3PosYLo:
	.fill NUM_OBJS2, (i * 10)
Objs3VelX:
	.fill NUM_OBJS2, random() > 0.5 ? -1 : 1
Objs3VelY:
	.fill NUM_OBJS2, 1

// ------------------------------------------------------------
//
.segment BSS "Pixie Work Lists"
PixieRowScreenPtrLo:
	.fill NUM_ROWS, $00
PixieRowScreenPtrHi:
	.fill NUM_ROWS, $00

PixieRowAttribPtrLo:
	.fill NUM_ROWS, $00
PixieRowAttribPtrHi:
	.fill NUM_ROWS, $00

// ------------------------------------------------------------
//
.segment ScreenRam "Screen RAM"
ScreenRam:
	.fill (LOGICAL_ROW_SIZE * NUM_ROWS), $00

// ------------------------------------------------------------
//
.segment MappedPixieWorkRam "Mapped Pixie Work RAM"
MappedPixieWorkTiles:
	.fill (LOGICAL_PIXIE_SIZE * NUM_ROWS), $00
MappedPixieWorkAttrib:
	.fill (LOGICAL_PIXIE_SIZE * NUM_ROWS), $00

// ------------------------------------------------------------
//
.segment PixieWorkRam "Pixie Work RAM"
PixieWorkTiles:
	.fill (LOGICAL_PIXIE_SIZE * NUM_ROWS), $00
PixieWorkAttrib:
	.fill (LOGICAL_PIXIE_SIZE * NUM_ROWS), $00

