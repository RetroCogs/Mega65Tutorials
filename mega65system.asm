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

    #if V200
        // Init V200 flags
        //
        #if DOUBLERRB
            // Enable RRB double buffer
            //
            lda #$08
            tsb $d031           //Clear bit3=V200
            lda #$00    		//Set CHRYSCL = 0
            sta $d05b
            lda #$80			//Clear bit7=NORRDEL
            trb $d051
            lda #$40    		//Set bit6=DBLRR
            tsb $d051
        #else
            // Enable RRB double buffer
            //
            lda #$08
            trb $d031           //Clear bit3=V200
            lda #$01    		//Set CHRYSCL = 1
            sta $d05b
            lda #$80			//Set bit7=NORRDEL
            tsb $d051
            lda #$40    		//Clear bit6=DBLRR
            trb $d051
        #endif
    #else 
        // Init V400 flags
        //
        lda #$08
        tsb $d031           //Set bit3=V400

        lda #$00    		//Set CHRYSCL = 0
        sta $d05b
    #endif

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

        lda #$08
        trb $d054

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
        _set16im((SCREEN_HEIGHT * VPIXELSCALE)/2, halfCharHeight)

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

// V400 no RRBDEL 1,1 

        _add16im(TopBorder, 1, TopBorder)
        _add16im(BotBorder, 1, BotBorder)

        _sub16im(charYPos, 0, charYPos)
        _sub16im(BotBorder, 0, BotBorder)

    !:

        // _sub16im(TopBorder, 8, TopBorder)
        // _add16im(BotBorder, 8, BotBorder)

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