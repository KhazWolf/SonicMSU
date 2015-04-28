;=========VRAM========
;(Each Address is One Word is Two Bytes)
;TILE SETS:
; BG1		$0000
; Also BG1	$4000
;TILE MAPS:
; BG1		$3C00
; Also BG1	$7C00

;=========RAM=========
.EQU frameCounter	$0100
.EQU frameSubCounter	$0102
.EQU volumeVar		$0104

.EQU MSU_STATUS		$2000
.EQU MSU_READ		$2001
.EQU MSU_ID		$2002
.EQU MSU_SEEK		$2000
.EQU MSU_SEEKBANK	$2002
.EQU MSU_TRACK		$2004
.EQU MSU_VOLUME		$2006
.EQU MSU_CONTROL	$2007

.EQU APUIO0		$2140
.EQU APUIO1		$2141
.EQU APUIO2		$2142
.EQU APUIO3		$2143

;== Include MemoryMap, HeaderInfo, and interrupt Vector table ==
.INCLUDE "header.inc"

;== Standard Init Code ==
.INCLUDE "init.inc"

;==========================================
; Main Code
;==========================================

.base $80	;FASTROM

.BANK 0 SLOT 0
.ORG 0
.SECTION "MainCode"

Start:
	sep #$20	;8 bit A
	stz $4200	; inhibit IRQs
	jsr killdma
	jsr waitblank
	jsr waitblank
	jsr waitblank
	jsr waitblank
	jsr waitblank		;I only included this part because I saw someone else do it

	InitSNES

	;=============================

	rep #$30		;16 bit AXY
	lda.w #$3C00
	sta.w $2116		;set VRAM write address to $3C00/$7C00 for Tile Map

	ldx.w #BlankTileMap	;In LoadVRAM X = 2 byte Source Address		
	lda.w #:BlankTileMap	;In LoadVRAM A = 1 byte Source Bank

	and.w #$00FF
	sep #$20		;8 bit A

	ldy.w #$0800		;In LoadVRAM Y = 2 byte Transfer Size (in bytes)
	jsr LoadVRAM		;TRANSFER 32 ROWS OF LO TILE MAP

	rep #$30		;16 bit AXY
	lda.w #$7C00
	sta.w $2116		;set VRAM write address to $3C00/$7C00 for Tile Map

	ldx.w #BlankTileMap	;In LoadVRAM X = 2 byte Source Address		
	lda.w #:BlankTileMap	;In LoadVRAM A = 1 byte Source Bank

	and.w #$00FF
	sep #$20		;8 bit A

	ldy.w #$0800		;In LoadVRAM Y = 2 byte Transfer Size (in bytes)
	jsr LoadVRAM		;TRANSFER 32 ROWS OF HI TILE MAP

	;=============================
	;SetupVideo

	sep #$20		;8 bit A

	lda #$09
	sta $2105		;Video mode 1, 8x8 tiles, 16 color BG1/BG2, 4 color BG3
	
	lda #$3C		;Set BG1's Tile Map offset to $3C00 (Word address) 
	sta $2107		;Tile Map size to 32x32

	stz $210B		;Set BG1's Character VRAM offset to $4000 (word address)
	
	lda #$01
	sta $212C		;BG1 Enabled - BG2/BG3/BG4/OAM Disabled

	lda.b #$8F
	sta.w $2100       	; Ensure screen OFF

	;Done SetupVideo
	;=============================

	jsr CheckForMSU

	rep #$20		;16 bit A
	stz frameCounter

	lda.w #$00D8		;216 for artificial vblank at end of picture
	sta.w $4209		;set up Vertical Video IRQ Point for Status Bar

	lda.w #$0003
	sta.w frameSubCounter

	sep #$20		;8 bit A

	lda.b #$21    
	sta.w $4200   		; Vertical Counter ONLY (for IRQ) and auto-joypad read NO VBLANKS

Frame:
	wai
	sep #$20		;8 bit A
	
	lda.w volumeVar
	cmp.b #$FF
	beq Frame
	ina
	sta.w volumeVar
	sta.w MSU_VOLUME
	jmp Frame


;============================================================================
VBlank:

	rti

;============================================================================
EndPicture:
	jml FastEndPicture
FastEndPicture:
	phk
	plb			;Set data bank to match program bank at $80 - for FASTROM

	sep #$20		;8 bit A
	lda.b #$80
	sta.w $2100       	; Ensure screen OFF, NO Brightness

	rep #$30		;16 bit AXY

	lda.w frameCounter
	bit.w #$0001		;test if even or odd frame.  For frame 0 write to LO VRAM
	bne _writeHI

	lda.w frameSubCounter
	beq _fourthAndSwitchLO
	cmp.w #$0003
	beq _firstTransferLO
	cmp.w #$0002
	beq _secondTransferLO
	bra _thirdTransferLO

_writeHI:
	lda.w frameSubCounter
	beq _fourthAndSwitchHI
	cmp.w #$0003
	beq _firstTransferHI
	cmp.w #$0002
	beq _secondTransferHI
	bra _thirdTransferHI

_firstTransferLO:
	lda.w #$0000
	bra _firstTransfer
_secondTransferLO:
	lda.w #$0E80
	jmp _secondTransfer
_thirdTransferLO:
	lda.w #$1D00
	jmp _thirdTransfer
_fourthAndSwitchLO:
	lda.w #$2B80
	jmp _fourthAndSwitch

_firstTransferHI:
	lda.w #$4000
	bra _firstTransfer
_secondTransferHI:
	lda.w #$4E80
	bra _secondTransfer
_thirdTransferHI:
	lda.w #$5D00
	jmp _thirdTransfer
_fourthAndSwitchHI:
	lda.w #$6B80
	jmp _fourthAndSwitch

;=======================================
_firstTransfer:
	sta.w $2116		;set VRAM write address to x + zero for Tile Set

	sep #$20		;8 bit A

	ldy.w #$1D00
	sty.w $4305		;$4305 = Transfer Size (2 bytes)
	lda.b #$09
	sta.w $4300		;$4300 = DMA Control (Word, Normal Non Increment) 
	lda.b #$18
	sta.w $4301		;$4301 = DMA Destination Register ($2118 = VRAM Data Port)
	lda.b #$01
	sta.w $420B		;$420B = Start DMA Transfer ($01 = DMA Channel 0)
				;TRANSFER TILE SET BLOCK 1

	lda.b #$0F
	sta.w $2100       	; Turn screen ON, at full Brightness

	lda.b #$02
	sta.w frameSubCounter

	lda $4211		;clear Interrupt

	rti

;=======================================
_secondTransfer:
	sta.w $2116		;set VRAM write address to x + zero for Tile Set

	sep #$20		;8 bit A

	ldy.w #$1D00
	sty.w $4305		;$4305 = Transfer Size (2 bytes)
	lda.b #$18
	sta.w $4301		;$4301 = DMA Destination Register ($2118 = VRAM Data Port)
	lda.b #$01
	sta.w $420B		;$420B = Start DMA Transfer ($01 = DMA Channel 0)
				;TRANSFER TILE SET BLOCK 2

	lda.b #$0F
	sta.w $2100       	; Turn screen ON, at full Brightness

	lda.b #$01
	sta.w frameSubCounter

	lda $4211		;clear Interrupt

	rti

;=======================================
_thirdTransfer:
	sta.w $2116		;set VRAM write address to x + zero for Tile Set

	sep #$20		;8 bit A

	ldy.w #$1D00
	sty.w $4305		;$4305 = Transfer Size (2 bytes)
	lda.b #$18
	sta.w $4301		;$4301 = DMA Destination Register ($2118 = VRAM Data Port)
	lda.b #$01
	sta.w $420B		;$420B = Start DMA Transfer ($01 = DMA Channel 0)
				;TRANSFER TILE SET BLOCK 3

	lda.b #$0F
	sta.w $2100       	; Turn screen ON, at full Brightness

	lda.b #$00
	sta.w frameSubCounter

	lda $4211		;clear Interrupt

	rti

;=======================================
_fourthAndSwitch:
	sta.w $2116		;set VRAM write address to x + $2B80 ($5700/2) for Tile Set
	pha			;store it as relative offset for tile map

	sep #$20		;8 bit A

	ldy.w #$1500
	sty.w $4305		;$4305 = Transfer Size (2 bytes)
	lda.b #$18
	sta.w $4301		;$4301 = DMA Destination Register ($2118 = VRAM Data Port)
	lda.b #$01
	sta.w $420B		;$420B = Start DMA Transfer ($01 = DMA Channel 0)
				;TRANSFER TILE SET BLOCK 4

	rep #$30		;16 bit AXY

	pla			;restore VRAM write address
	clc
	adc.w #$1080		;Map is Block4 address + $1080
	sta.w $2116		;set VRAM write address to $3C00/$7C00 for Tile Map

	sep #$20		;8 bit A

	ldy.w #$06C0		;In LoadVRAM Y = 2 byte Transfer Size (in bytes)
	sty.w $4305		;$4305 = Transfer Size (2 bytes)
	lda.b #$18
	sta.w $4301		;$4301 = DMA Destination Register ($2118 = VRAM Data Port)
	lda.b #$01
	sta.w $420B		;$420B = Start DMA Transfer ($01 = DMA Channel 0)
				;TRANSFER TILE MAP

	sep #$20		;8 bit A

	stz.w $2121		;set CGRAM write address to zero - begin writing at first palette

	ldy.w #$0100		;In LoadVRAM Y = 2 byte Transfer Size (in bytes)
	sty.w $4305		;$4305 = Transfer Size (2 bytes)
	lda.b #$08
	sta.w $4300		;$4300 = DMA Control (Byte, Normal Non Increment)
	lda.b #$22
	sta.w $4301		;$4301 = DMA Destination Register ($2122 = CGRAM Data Port)
	lda.b #$01
	sta.w $420B		;$420B = Start DMA Transfer ($01 = DMA Channel 0)
				;TRANSFER PALETTES

	lda.w frameCounter
	bit.b #$01
	bne _switchToHi

	lda.b #$3C		;Set BG1's Tile Map offset to $3C00 (Word address) 
	sta.w $2107		;Tile Map size to 32x32

	stz.w $210B		;Set BG1's Character VRAM offset to $0000 (word address)
	bra _doneSwitch

_switchToHi:
	lda.b #$7C		;Set BG1's Tile Map offset to $7C00 (Word address) 
	sta.w $2107		;Tile Map size to 32x32

	lda.b #$04
	sta.w $210B		;Set BG1's Character VRAM offset to $4000 (word address)

_doneSwitch:
	lda.b #$0F
	sta.w $2100       	; Turn screen ON, at full Brightness

	lda.b #$03
	sta.w frameSubCounter

	rep #$30		;16 bit A
	
	lda.w frameCounter
	ina
	cmp.w #$053E
	beq _doneVideo

	sta.w frameCounter	;increment frame counter

	sep #$20		;8 bit A
	lda $4211		;clear Interrupt

	rti

_doneVideo:
	sep #$20		;8 bit A
	stz $4200		;inhibit IRQs
	lda.b #$80
	sta.w $2100       	;Turn screen OFF

	STP			;Hammertime

;============================================================================
LoadVRAM:
	php
	stx $4302	;$4302 = Source Address (2 bytes)
	sta $4304	;$4304 = Source Bank (1 byte)
	sty $4305	;$4305 = Transfer Size (2 bytes)
	lda #$01
	sta $4300	;$4300 = DMA Control (Write words, LH)
	lda #$18
	sta $4301	;$4301 = DMA Destination Register ($2118 = VRAM Data Port)
	lda #$01
	sta $420B	;$420B = Start DMA Transfer ($01 = DMA Channel 0)
	plp
	rts

;============================================================================
DMAPalette:
	php
	stx $4302	;$4302 = Source Address (2 bytes)
	sta $4304	;$4304 = Source Bank (1 byte)
	sty $4305	;$4305 = Transfer Size (2 bytes)
	stz $4300	;$4300 = DMA Control (byte writes to $2122 only)
	lda #$22
	sta $4301	;$4301 = DMA Destination Register ($2122 = CGRAM Data Port)
	lda #$01
	sta $420B	;$420B = Start DMA Transfer ($01 = DMA Channel 0)
	plp
	rts

;============================================================================
PlayMSUTrack:
	php

	sep #$20
	rep #$10

	; WLA-DX
	lda #$FF
	sta MSU_VOLUME
	ldx #$0001	; Writing a 16-bit value will automatically
	stx MSU_TRACK	; set $2005 as well, so this is easy.
	lda #$01	; Set audio state to play, no repeat.
	sta MSU_CONTROL
	; The MSU1 will now start playing.
	; Use lda #$03 to play a song repeatedly.

	plp
	rts

;============================================================================
BlankTileMap:

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF

	.dw $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF, $03BF


;============================================================================
; ALL CODE BELOW THIS POINT WAS NOT WRITTEN BY ME I TAKE NO CREDIT
;============================================================================

killdma:
	stz $420b
	stz $420c
	rts

;============================================================================
waitblank:
	lda $4212
	and #$80
	bne waitblank
waitblank2:
	lda $4212
	and #$80
	beq waitblank2
	rts

;============================================================================
CheckForMSU:
   lda MSU_ID
   cmp #'S'
   beq +
   brl NoMSU
+   lda MSU_ID+1
   cmp #'-'
   bne NoMSU
   lda MSU_ID+2
   cmp #'M'
   bne NoMSU
   lda MSU_ID+3
   cmp #'S'
   bne NoMSU
   lda MSU_ID+4
   cmp #'U'
   bne NoMSU
   lda MSU_ID+5
   cmp #'1'
   bne NoMSU

MSUFound:
   php			; SPC700 pass-through enabling needed

   sep #$20
   rep #$10

   sei               ; Disable NMI & IRQ
   stz $4200

; ---- Begin upload

   ldy #$0002
   jsr spc_begin_upload

; ---- Upload SPC700 pass-through code

   ldx #$0000
-
   lda.w spccode,x
   jsr spc_upload_byte
   inx
   cpy #41               ; size of spc code
   bne -

; ---- Execute loader

   ldy #$0002
   jsr spc_execute

   cli
   plp

   jsr PlayTrack

	rep #$30		;16 bit XY
	sep #$20		;8 bit A

	ldx.w #$0000		;Seek To $0000:0000, In The Data .MSU File
	stx.w MSU_SEEK		;$2000 MSU1 Seek Register
	ldx.w #$0000		;Set Seek Bank Register
	stx.w MSU_SEEKBANK	;$2002 MSU1 Seek Bank Register    

MSUDataBusySpin:
	bit.w MSU_STATUS	;$2000 MSU1 Status Register
	bmi MSUDataBusySpin	;Wait For MSU1 Data Busy Flag Status Bit To Clear

	;Setup Tile DMA On Channel 0
	lda.b #$09
	sta.w $4300		;Set DMA Mode (Word, Normal Non Increment) ($4300: DMA Control)
	lda.b #$18		;Set Destination Register ($2118: VRAM Write)
	sta.w $4301		;$4301 DMA Destination
	ldx.w #MSU_READ		;Source Data
	stx.w $4302		;Store Data Offset Into DMA Source Offset ($4302: DMA Source)
	stz.w $4304		;Store Zero Into DMA Source Bank ($4304: Source Bank)

   rts

NoMSU:
	;No MSU1 media enhancement hardware found!
;	bra ForeverLoop
	rts

PlayTrack:
   lda #$00
   sta MSU_VOLUME
   ldx #$0001
   stx MSU_TRACK
-   bit MSU_STATUS   ; Wait for the Audio Busy bit to clear.
   bvs -
   lda #$01   ; Set audio state to play, no repeat.
   sta MSU_CONTROL
   lda #$00
   sta MSU_VOLUME	;initialize volume to zero and ramp up
   sta volumeVar
rts

ForeverLoop:
   wai               ; wait for next frame
   bra ForeverLoop



; ************************ SPC700 pass-through *************************

spc_begin_upload:
   sty APUIO2            ; Set address

   ldy #$BBAA            ; Wait for SPC
-
   cpy APUIO0
   bne -

   lda #$CC            ; Send acknowledgement
   sta APUIO1
   sta APUIO0

-                      ; Wait for acknowledgement
   cmp APUIO0
   bne -

   ldy #0               ; Initialize index
rts



spc_upload_byte:
   sta APUIO1

   tya               ; Signal it's ready
   sta APUIO0
-                       ; Wait for acknowledgement
   cmp APUIO0
   bne -

   iny

rts



spc_execute:
   sty APUIO2

   stz APUIO1

   lda APUIO0
   inc a
   inc a
   sta APUIO0

; Wait for acknowledgement
-
   cmp APUIO0
   bne -

rts


;============================================================================
spccode:
	.db $e8, $6c		; - MOV A, #$6c ; FLG register
	.db $c4, $f2		; MOV $f2, A
	.db $e8, $20		; MOV A, #$20   ; unmute, disable echo
	.db $c4, $f3		; MOV $f3, A
	.db $78, $20, $f3	; CMP $f3, #$20
	.db $d0, $f3		; BNE -

	.db $e8, $2c		; - MOV A, #$2c ; Echo volume left
	.db $c4, $f2		; MOV $f2, A
	.db $e8, $00		; MOV A, #$00   ; silent
	.db $c4, $f3		; MOV $f3, A
	.db $78, $00, $f3	; CMP $f3, #$00
	.db $d0, $f3		; BNE -

	.db $e8, $3c		; - MOV A, #$3c ; Echo volume right
	.db $c4, $f2		; MOV $f2, A
	.db $e8, $00		; MOV A, #$00   ; silent
	.db $c4, $f3		; MOV $f3, A
	.db $78, $00, $f3	; CMP $f3, #$00
	.db $d0, $f3		; BNE -

	.db $2f, $fe		; - BRA -

;============================================================================

.ENDS
