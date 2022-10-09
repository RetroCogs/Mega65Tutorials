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

.const MAX_WIDTH = HORIZONTAL_CENTER - HSCROLLAMOUNT
.print "MAX_WIDTH = " + MAX_WIDTH

.const MAX_HEIGHT = VERTICAL_CENTER - VSCROLLAMOUNT
.print "MAX_HEIGHT = " + MAX_HEIGHT

.if ((TOP_BORDER - VSCROLLAMOUNT) < 0) .error "Vertical height too much, max value = " + MAX_HEIGHT
.if ((LEFT_BORDER - HSCROLLAMOUNT) < 0) .error "Horizontal width too much, max value = " + MAX_WIDTH

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
	lda #[addr & $ff]
	sta $d060
	lda #[[addr & $ff00]>>8]
	sta $d061
	lda #[[addr & $ff0000]>>16]
	sta $d062
	lda #[[[addr & $ff0000]>>24] & $0f]
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

.macro VIC4_SetLogicalRowSize(rowWidth) {
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

