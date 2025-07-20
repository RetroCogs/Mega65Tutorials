// ------------------------------------------------------------
// Define Horizontal and Vertical centers, border widths and 
// screen positions are created based on these values.
//
.const HORIZONTAL_CENTER = 400

// PAL and NTSC have different vertical centers
#if IS_NTSC
.const VERTICAL_CENTER = 242
#else
.const VERTICAL_CENTER = 304
#endif

// H&V PIXELSCALE are used because H320&V200 pixel size is twice the size of H640&V400
#if H320
.const HPIXELSCALE = 2
#else
.const HPIXELSCALE = 1
#endif

#if V200
.const VPIXELSCALE = 2
#else
.const VPIXELSCALE = 1
#endif

.const HSCROLLAMOUNT = 8 * HPIXELSCALE
.const VSCROLLAMOUNT = 8 * VPIXELSCALE

// Calculate Left, Top and Bottom border sizes based on visble screen area and
// horizontal and vertial centers
//
.const LEFT_BORDER = (HORIZONTAL_CENTER - ((SCREEN_WIDTH * HPIXELSCALE) / 2))
.const TOP_BORDER = (VERTICAL_CENTER - ((SCREEN_HEIGHT * VPIXELSCALE) / 2))
.const BOTTOM_BORDER = (VERTICAL_CENTER + ((SCREEN_HEIGHT * VPIXELSCALE) / 2))

.const TEXTYPOS = TOP_BORDER

.const MAX_WIDTH = HORIZONTAL_CENTER - HSCROLLAMOUNT
.print "MAX_WIDTH = " + MAX_WIDTH

.const MAX_HEIGHT = VERTICAL_CENTER - VSCROLLAMOUNT
.print "MAX_HEIGHT = " + MAX_HEIGHT

//.if ((TOP_BORDER - VSCROLLAMOUNT) < 0) .error "Vertical height too much, max value = " + MAX_HEIGHT
//.if ((LEFT_BORDER - HSCROLLAMOUNT) < 0) .error "Horizontal width too much, max value = " + MAX_WIDTH

// ------------------------------------------------------------
//
.macro BasicUpstart65(addr) {
* = $2001 "BasicUpstart65"

	.var addrStr = toIntString(addr)

	.byte $09,$20 //End of command marker (first byte after the 00 terminator)
	.byte $0a,$00 //10
	.byte $fe,$02,$30,$00 //BANK 0
	.byte <end, >end //End of command marker (first byte after the 00 terminator)
	.byte $14,$00 //20
	.byte $9e //SYS
	.text addrStr
	.byte $00
end:
	.byte $00,$00	//End of basic terminators
}

.macro mapHi(source, target, blocks) {
	.var sourceMB = (source & $ff00000) >> 20
	.var sourceOffset = ((source & $00fff00) - target)
	.var sourceOffHi = sourceOffset >> 16
	.var sourceOffLo = (sourceOffset & $0ff00 ) >> 8
	.var bitHi = blocks << 4

	ldy #sourceOffLo
	ldz #[sourceOffHi + bitHi]
}

.macro mapLo(source, target, blocks) {
	.var sourceMB = (source & $ff00000) >> 20
	.var sourceOffset = ((source & $00fff00) - target)
	.var sourceOffHi = sourceOffset >> 16
	.var sourceOffLo = (sourceOffset & $0ff00 ) >> 8
	.var bitLo = blocks << 4

	lda #sourceOffLo
	ldx #[sourceOffHi + bitLo]
}

.macro unmapMemory()
{
	lda #$00
	tax
	tay
	taz
	map
	eom
}

// _set8im - store an 8bit constant to a memory location
.macro _set8im(value, dst)
{
	lda #value
	sta dst
}

// _add8im - add a 8bit constant to a memory location, store in result
.macro _add8im(src, value, dst)
{
	clc
	lda src
	adc #value
	sta dst
}

// _add8 - add a 8bit value to a memory location, store in result
.macro _add8(src, value, dst)
{
	clc
	lda src
	adc value
	sta dst
}

// _sub8im - sub a 8bit constant to a memory location, store in result
.macro _sub8im(src, value, dst)
{
	sec
	lda src
	sbc #value
	sta dst
}

// _sub8 - sub a 8bit value to a memory location, store in result
.macro _sub8(src, value, dst)
{
	sec
	lda src
	sbc value
	sta dst
}

// _set16 - copy a 16bit memory location to dest memory location
.macro _set16(src, dst)
{
	lda src+0
	sta dst+0
	lda src+1
	sta dst+1
}

// _set16ofs - copy a 16bit memory location to dest memory location and add offset
.macro _set16ofs(src, ofs, dst)
{
	clc
	lda src+0
	adc #<ofs
	sta dst+0
	lda src+1
	adc #>ofs
	sta dst+1
}

// _set16im - store a 16bit constant to a memory location
.macro _set16im(value, dst)
{
	lda #<value
	sta dst+0
	lda #>value
	sta dst+1
}

// _add16im - add a 16bit constant to a memory location, store in result
.macro _add16im(src, value, dst)
{
	clc						// ensure carry is clear
	lda src+0				// add the two least significant bytes
	adc #<value
	sta dst+0
	lda src+1				// add the two most significant bytes
	adc #>value
	sta dst+1
}

// _add16 - add a 16bit value to a memory location, store in result
.macro _add16(src, value, dst)
{
	clc						// ensure carry is clear
	lda src+0				// add the two least significant bytes
	adc value
	sta dst+0
	lda src+1				// add the two most significant bytes
	adc value+1
	sta dst+1
}

// _sub16im - sub a 16bit constant to a memory location, store in result
.macro _sub16im(src, value, dst)
{
	sec						// SET CARRY 
	lda src+0 				// LOW HALF OF 16-BIT NUMBER IN $C0 AND $C1 
	sbc #<value				// LOW HALF OF 16-BIT NUMBER IN $B0 AND $B1 
	sta dst+0
	lda src+1 				// HIGH HALF OF 16-BIT NUMBER IN $C0 AND $C1 
	sbc #>value 			// HIGH HALF OF 16-BIT NUMBER IN $B0 AND $B1 
	sta dst+1 
}

// _sub16 - sub a 16bit value to a memory location, store in result
.macro _sub16(src, value, dst)
{
	sec						// SET CARRY 
	lda src+0 				// LOW HALF OF 16-BIT NUMBER IN $C0 AND $C1 
	sbc value				// LOW HALF OF 16-BIT NUMBER IN $B0 AND $B1 
	sta dst+0
	lda src+1 				// HIGH HALF OF 16-BIT NUMBER IN $C0 AND $C1 
	sbc value+1 			// HIGH HALF OF 16-BIT NUMBER IN $B0 AND $B1 
	sta dst+1 
}

// _and16im - and a 16bit constant with a memory location, store in result
.macro _and16im(src, value, dst)
{
	lda src+0
	and #<value
	sta dst+0
	lda src+1
	and #>value
	sta dst+1
}

// _and16 - and a 16bit value with a memory location, store in result
.macro _and16(src, value, dst)
{
	lda src+0
	and value+0
	sta dst+0
	lda src+1
	and value+1
	sta dst+1
}

.macro _swap16(ptr1, ptr2)
{
	lda ptr1
	pha
	lda ptr1+1
	pha
	_set16(ptr2,ptr1)
	pla
	sta ptr2+1
	pla
	sta ptr2
}

// _set24im - store a 24bit constant to a memory location
.macro _set24im(value, dst)
{
	lda #<value
	sta dst+0
	lda #>value
	sta dst+1
	lda #[value >> 16]
	sta dst+2
}

// _set24 - store a 24bit value to a memory location
.macro _set24(value, dst)
{
	lda value+0
	sta dst+0
	lda value+1
	sta dst+1
	lda value+2
	sta dst+2
}

// _add24im - add a 24bit constant to a memory location, store in result
.macro _add24im(src, value, dst)
{
	clc
	lda src+0
	adc #<value
	sta dst+0
	lda src+1
	adc #>value
	sta dst+1
	lda src+2
	adc #[value >> 16]
	sta dst+2
}

// _add24 - add a 24bit value to a memory location, store in result
.macro _add24(src, value, dst)
{
	clc
	lda src+0
	adc value
	sta dst+0
	lda src+1
	adc value+1
	sta dst+1
	lda src+2
	adc value+2
	sta dst+2
}

// _sub24im - sub a 24bit constant to a memory location, store in result
.macro _sub24im(src, value, dst)
{
	sec 
	lda src+0 
	sbc #<value 
	sta dst+0
	lda src+1 
	sbc #>value 
	sta dst+1 
	lda src+2 
	sbc #[value >> 16] 
	sta dst+2
}

// _sub24 - sub a 24bit value to a memory location, store in result
.macro _sub24(src, value, dst)
{
	sec
	lda src+0
	sbc value
	sta dst+0
	lda src+1
	sbc value+1
	sta dst+1 
	lda src+2
	sbc value+2
	sta dst+2
}

.macro _half24(srcdst)
{
	lda srcdst+2
	cmp #$80
	ror
	ror srcdst+1
	ror srcdst+0
	sta srcdst+2
}

// _set32im - store a 32bit constant to a memory location
.macro _set32im(value, dst)
{
	lda #<value
	sta dst+0
	lda #>value
	sta dst+1
	lda #[value >> 16]
	sta dst+2
	lda #[value >> 24]
	sta dst+3
}

// _set32 - store a 32bit value to a memory location
.macro _set32(value, dst)
{
	lda value+0
	sta dst+0
	lda value+1
	sta dst+1
	lda value+2
	sta dst+2
	lda value+3
	sta dst+3
}

// _add32im - add a 32bit constant to a memory location, store in result
.macro _add32im(src, value, dst)
{
	clc
	lda src+0
	adc #<value
	sta dst+0
	lda src+1
	adc #>value
	sta dst+1
	lda src+2
	adc #[value >> 16]
	sta dst+2
	lda src+3
	adc #[value >> 24]
	sta dst+3
}

// _sub32im - sub a 32bit constant to a memory location, store in result
.macro _sub32im(src, value, dst)
{
	sec 
	lda src+0 
	sbc #<value 
	sta dst+0
	lda src+1 
	sbc #>value 
	sta dst+1 
	lda src+2 
	sbc #[value >> 16] 
	sta dst+2
	lda src+3 
	sbc #[value >> 24] 
	sta dst+3 
}

.macro enable40Mhz() {
	lda #$41
	sta $00 	//40 Mhz mode
}

.macro enableVIC4Registers () {
	lda #$00
	tax 
	tay 
	taz 
	map
	eom

	lda #$47	//Enable VIC IV
	sta $d02f
	lda #$53
	sta $d02f
}

.macro disableCIAInterrupts() {
	//Disable CIA interrupts
	lda #$7f
	sta $dc0d
	sta $dd0d
}

.macro disableC65ROM() {
	//Disable C65 rom protection using
	//hypervisor trap (see mega65 manual)	
	lda #$70
	sta $d640
	eom
	//Unmap C65 Roms $d030 by clearing bits 3-7
	lda #%11111000
	trb $d030
}

.macro VIC4_SetScreenPtr(addr) {
	lda #[[addr] & $ff]
	sta $d060
	lda #[[addr >> 8] & $ff]
	sta $d061
	lda #[[addr >> 16] & $ff]
	sta $d062
	lda #[[addr >> 24] & $ff]
	sta $d063
}

.macro VIC4_SetCharPtr(addr) {
	lda #[addr & $ff]
	sta $d068
	lda #[[addr & $ff00]>>8]
	sta $d069
	lda #[[addr & $ff0000]>>16]
	sta $d06a
}

.macro VIC4_SetRowWidth(rowWidth) {
	lda #<rowWidth
	sta $d058
	lda #>rowWidth
	sta $d059
}

.macro VIC4_SetNumCharacters(numChrs) {
	lda #<numChrs
	sta $d05e
	lda $d063
	and #$cf
	ora #((>numChrs) & $03) << 4
	sta $d063
}

.macro VIC4_SetNumRows(numRows) {
	lda #numRows
	sta $d07b 
}

.macro RunDMAJob(JobPointer) {
		lda #[JobPointer >> 16]
		sta $d702
		sta $d704
		lda #>JobPointer
		sta $d701
		lda #<JobPointer
		sta $d705
}
.macro DMAHeader(SourceBank, DestBank) {
		.byte $0A // Request format is F018A
		.byte $80, SourceBank
		.byte $81, DestBank
}
.macro DMAStep(SourceStep, SourceStepFractional, DestStep, DestStepFractional) {
		.byte $82, SourceStepFractional
		.byte $83, SourceStep
		.byte $84, DestStepFractional
		.byte $85, DestStep		
}
.macro DMADestStep(DestStep, DestStepFractional) {
		.byte $84, DestStepFractional
		.byte $85, DestStep		
}
.macro DMADisableTransparency() {
		.byte $06
}
.macro DMAEnableTransparency(TransparentByte) {
		.byte $07 
		.byte $86, TransparentByte
}
.macro DMACopyJob(Source, Destination, Length, Chain, Backwards) {
	.byte $00 //No more options
	.if(Chain) {
		.byte $04 //Copy and chain
	} else {
		.byte $00 //Copy and last request
	}	
	
	.var backByte = 0
	.if(Backwards) {
		.eval backByte = $40
		.eval Source = Source + Length - 1
		.eval Destination = Destination + Length - 1
	}
	.word Length //Size of Copy

	//byte 04
	.word Source & $ffff
	.byte [Source >> 16] + backByte

	//byte 07
	.word Destination & $ffff
	.byte [[Destination >> 16] & $0f]  + backByte
	.if(Chain) {
		.word $0000
	}
}


.macro DMAFillJob(SourceByte, Destination, Length, Chain) {
	.byte $00 //No more options
	.if(Chain) {
		.byte $07 //Fill and chain
	} else {
		.byte $03 //Fill and last request
	}	
	
	.word Length //Size of Copy
	//byte 4
	.word SourceByte
	.byte $00
	//byte 7
	.word Destination & $ffff
	.byte [[Destination >> 16] & $0f] 
	.if(Chain) {
		.word $0000
	}
}


.macro DMAMixJob(Source, Destination, Length, Chain, Backwards) {
	.byte $00 //No more options
	.if(Chain) {
		.byte $04 //Mix and chain
	} else {
		.byte $00 //Mix and last request
	}	
	
	.var backByte = 0
	.if(Backwards) {
		.eval backByte = $40
		.eval Source = Source + Length - 1
		.eval Destination = Destination + Length - 1
	}
	.word Length //Size of Copy
	.word Source & $ffff
	.byte [Source >> 16] + backByte
	.word Destination & $ffff
	.byte [[Destination >> 16] & $0f]  + backByte
	.if(Chain) {
		.word $0000
	}
}

