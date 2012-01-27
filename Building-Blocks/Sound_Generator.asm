; Sound_Generator.asm
; -------------------------------------------------------------------------
; begin                 : 2011-12-10
; copyright             : Copyright (C) 2011 by Manfred Morgner
; email                 : manfred.morgner@gmx.net
; =========================================================================
;                                                                         |
;   This program is free software; you can redistribute it and/or modify  |
;   it under the terms of the GNU General Public License as published by  |
;   the Free Software Foundation; either version 2 of the License, or     |
;   (at your option) any later version.                                   |
;                                                                         |
;   This program is distributed in the hope that it will be useful,       |
;   but WITHOUT ANY WARRANTY; without even the implied warranty of        |
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         |
;   GNU General Public License for more details.                          |
;                                                                         |
;   You should have received a copy of the GNU General Public License     |
;   along with this program; if not, write to the                         |
;                                                                         |
;   Free Software Foundation, Inc.,                                       |
;   59 Temple Place Suite 330,                                            |
;   Boston, MA  02111-1307, USA.                                          |
; =========================================================================

; Arduino Nano 3.0 shipped with atmega168 but later with atmega328
.DEVICE atmega328
;.DEVICE atmega168

; ============================================================================================================
; Documentation
;
; Expectations
;
; Target of this code is to implement a wave form generator (wave form output in binary numbers for D/A
; conversion) to fullfill the following requests in this order
;
;   1) Shortest possbile code (in processing cycles)
;   2) Minimum footprint of registers
;   3) Highest possbile composition rate constence
;   4) The potential so deal with changing wave forms (=sounds)
;;
; Solution
;
;   1) Multiple sounds will be stored in cseg (FLASH)
;   2) One at a time will be moved to RAM to be 'played' from there
;   3) A sound is exactly 257 Bytes long and ends with the same value it starts
;   4) The current sound in RAM will start at 'YH:0x00' and ends at 'YH:0xFF'
;   5) One round is stored in 256 bytes, so iterating YL will work like an infinite buffer rotation
;
; Using these conditions, the only persitant registers wie need are: 'YH:YL' and a 8 bit sample accumulator.
; Also we don't need 16bit pointer arithmetics, border checks, other status accumulators.

; ============================================================================================================
; DATA SEGMENT (RAM)

.dseg
     ; the current sound is 256 samples, we have to ensure, low(adr) can be NULL Sample will be adressed by Y 
     ; where YH is fix and YL is pSample. This way we do not need any copy of Y-start address, don't need
     ; pSample as extra  register (pSample is an alias to YL), don't need pointer arithmetics and so  have the
     ; fastest possibel address calculation for sound production (which should use the shortest amount of time)
     ; For this we pay with 256 bytes of unused but reserved RAM.
     abSound: .Byte 256*2

; ============================================================================================================
; CODE SEGMENT (FLASH)

.cseg

.org 0x0000
     rjmp    setup              ; register 'setup' as Programm Start Routine
.org OVF1addr
     rjmp    interrupt_timer_1  ; register 'interrupt_timer_1' as Timer1 Overflow Routine

; ============================================================================================================
; definitionsection

.equ inpTrigger  = PINB  ; input PORT for digital triggers (Sound Signal Test)
.equ mskTrigger  = 0x03  ; input bits (2 => 0000 0011)

.equ ctlSignal   = DDRB  ; port control register
.equ outSignal   = PORTB ; output PORT for digital signals (Trigger Feedback)
.equ mskSignal   = 0x3C  ; output bits (4 => 0011 1100)

.equ ctlSound    = DDRD  ; port control register
.equ outSound    = PORTD ; output PORT for DA converter (8bit sound sample output)

; ------------------------------------------------------------------------------------------------------------
;  A4 = 440 Hz
; Interrupt Generator has to be adjusted to 256*'A5' = 112640 Hz => 142 cycles to do what's necessary
; 2 byte timing, here with value 0xFF72 (142) for 112640 Hz on 16MHz MC
.equ    TPBH     = 0xff  ; timer preset (high)
.equ    TPBL     = 0x7F  ; timer preset (low)

; ------------------------------------------------------------------------------------------------------------
; for gavrasm (should be known by other assembler)
;def X           = r26   ; X word
;def XL          = r26   ; X low byte
;def XH          = r27   ; X high byte
.def Y           = r28   ; Y word
.def YL          = r28   ; Y low byte
.def pSample     = r28   ; alias to YL, will be initialised by YL by sound-to-RAM copy procedure
.def YH          = r29   ; Y high byte
.def Z           = r30   ; Z word
.def ZL          = r30   ; Z low byte
.def ZH          = r31   ; Z high byte

; ------------------------------------------------------------------------------------------------------------
; 'low registers'

.def bTPBL       = r1    ; timer preset (low)
.def bTPBH       = r2    ; timer preset (high)

.def bCount1     = r3    ; generic counter
.def bSample     = r4    ; value of curent sample in sound
.def vecOrient   = r5    ; object lies upright

; ------------------------------------------------------------------------------------------------------------
; 'high registers' - because these values need to have registers higher than 15
.def valNull     = r16   ; a NULL because of MC restrictions
.def bTemp       = r17   ; a temporary register
.def bInput      = r19   ; input value

; ============================================================================================================
; Programm Initialisation

; Interrupt Timing Setup

    setup:
            cli                                         ; no interrupts while setting up interrupts

            ldi     bTemp,        low (RAMEND)          ; initializing stack pointer
            out     SPL,          bTemp                 ; 
            ldi     bTemp,        high(RAMEND)          ; 
            out     SPH,          bTemp                 ; 

; prepair timer interrupt

            ldi     bTemp,        0x00                  ; set time1 to "no waveform generation & no compare match interrupt"
            sts     TCCR1A,       bTemp                 ; 
            ldi     bTemp,        0x01                  ; set timer1 prescaler to 1
            sts     TCCR1B,       bTemp                 ; 
            ldi     bTemp,        0x02                  ; set timer1 to overflow interrupt timer
            sts     TIMSK1,       bTemp                 ; 

; define IO ports

            ldi     bTemp,        0xFF                  ; pins to output (all)
            out     ctlSound,     bTemp                 ; set all pins to output on DDRsound for sound

            ldi     bTemp,        mskSignal             ; output mask for signals 0xXC (NOT 0xX3)
            out     ctlSignal,    bTemp                 ; set output pins for signals

            ldi     bTemp,        mskTrigger            ; input bitmask
            out     outSignal,    bTemp                 ; set input mask for pullup bits for input triggers

; initialize destination/source address for RAM-sound starting by YL=0
            ldi     YL,           low (abSound)         ; sound wave into RAM
            ldi     YH,           high(abSound)         ; 
            cpse    YL,           valNULL               ; is YL already NULL ?
            inc     YH                                  ; no => we use the next higher adress with YL = 0

; == initialize registers by name

; initialize timing constants
            ldi     bTemp,        TPBL                  ; timer preset (low)
            mov     bTPBL,        bTemp                 ; 
            ldi     bTemp,        TPBH                  ; timer preset (high)
            mov     bTPBH,        bTemp                 ; 

            clr     valNULL                             ; the NULL
            clr     bSample                             ; no sample value - no noise

; == move current sound to RAM

            rcall   Sound2RAM                           ; copy wave set from FLASH to RAM + sets pSample to NULL

; set timer for first interrupt

            sts     TCNT1L,       valNULL               ; 1 initial time setup. we are setting up, 
            sts     TCNT1H,       valNULL               ; 1 the first periode does no matter
            sei                                         ; 1 now we are ready to receive interrupts

; == this is unnerving - but necessary

    forever:
            rjmp    forever

; ============================================================================================================
; sub routine: copy the current sound to RAM, timing: 1800 cycles = 0.1125 ms

    Sound2RAM:
            ldi     ZL,           low (awSoundFlash*2)  ; 1   sound address in FLASH
            ldi     ZH,           high(awSoundFlash*2)  ; 1   
            add     ZH,           vecOrient             ; 1   Z + 256*'orientation' to address the chosen sound

            clr     YL                                  ; 1   one times 0 to 0 makes 256 (sound bytes)
    CopyByte:                                           ; 256*7 = 1792 cycles = 0.112 ms
            lpm     bTemp,        Z+                    ; 3   read next byte from FLASH
            st      Y,            bTemp                 ; 1   write this byte to RAM
            inc     YL                                  ; 1   one sample done
            brne    CopyByte                            ; 2-1 if not NULL we have to copy another one

            ret                                         ; 4   done

; ============================================================================================================
; START OF SOUND INTERRUPT SERVICE ROUTINE

    interrupt_timer_1:

; set timer for next interrupt - we have no time doing other things, for now

            sts     TCNT1L,       bTPBL                 ; 1 
            sts     TCNT1H,       bTPBH                 ; 1 

; not to forget, we are in constante time frame, so we output the sample from the previous round

;lsr bSample
            out     outSound,     bSample               ; send sample to output
            clr     bSample                             ; we had it played, so we clear it off

; if the last sound is not finished yet, pSample is not NULL

            tst     pSample                             ; if the relative sample pointer is not NULL
            brne    play                                ; we have to play the sound to finish the wave at least

rjmp play

; read input sensors to check if we have to play sound
; we are sure that we only step through the following query code if the sound had not allready started!
; so we may spend some time here - if we have to analyse something

            in      bInput,       inpTrigger            ; 1   read input
            com     bInput                              ; 1   invert input bits (they come in inverted)
            andi    bInput,       mskTrigger            ; 1   check if any valid signal appeared
            brne    play                                ; 1-2 if so, we have to play the sound
            reti                                        ; 4   otherwise, we are done

; we simply have to read the next sample value

    play:

; get the next sample but don't output because here, here we have no constant time frame anymore

            ld      bSample,      Y                     ; we read the sample to the sample accumulator
            inc     pSample                             ; next time, next sample (pSample is YL)

            reti                                        ; done after reading next sound sample

; ============================================================================================================

awSoundFlash:                                           ; little endian words - 32 per line

; The length of a sound is (in truth) 257 samples! we play 256 samples per sound repitition and expect the
; next sample after the last in store to be the first of the new (and old) curve. Thus we dont repeat a sample
; This is espcialy to know if you wsh to design new sounds.
; Remember: Ths whole programm is only for 256bytes stored samples per sound. There is no way around this
; Limitation besides to rewrite most of the code and redesing the sound length recognition. Because:
; This code has none. It relies on the fact, that a byte can count from 0 to 255 (which makes 256 steps)
; The first sample of a sound has to be '0' for accoustic reasons.

; possible resolution
; ======================
; lable  instrument
; ----------------------
; uprt   xylophone wood
; left   organ key
; down   xylophone metal
; rght   piano
; back   drum
; frnt   bell


; sin( x ) with x from 0 to 2pi/257*256 

UPRT: .dw 0x0000,0x0000,0x0101,0x0202,0x0303,0x0504,0x0706,0x0908,0x0C0A,0x0E0D,0x1110,0x1413,0x1816,0x1C1A,0x201E,0x2422,0x2826,0x2D2B,0x322F,0x3734,0x3C3A,0x423F,0x4744,0x4D4A,0x5350,0x5855,0x5E5B,0x6461,0x6B67,0x716E,0x7774,0x7D7A
      .dw 0x8380,0x8A87,0x908D,0x9693,0x9C99,0xA29F,0xA8A5,0xAEAB,0xB4B1,0xB9B7,0xBFBC,0xC4C1,0xC9C7,0xCECC,0xD3D1,0xD8D5,0xDCDA,0xE0DE,0xE4E2,0xE8E6,0xEBEA,0xEFED,0xF1F0,0xF4F3,0xF7F5,0xF9F8,0xFAFA,0xFCFB,0xFDFD,0xFEFE,0xFFFE,0xFFFF
      .dw 0xFFFF,0xFFFF,0xFEFE,0xFDFE,0xFCFD,0xFAFB,0xF9FA,0xF7F8,0xF4F5,0xF1F3,0xEFF0,0xEBED,0xE8EA,0xE4E6,0xE0E2,0xDCDE,0xD8DA,0xD3D5,0xCED1,0xC9CC,0xC4C7,0xBFC1,0xB9BC,0xB4B7,0xAEB1,0xA8AB,0xA2A5,0x9C9F,0x9699,0x9093,0x8A8D,0x8387
      .dw 0x7D80,0x777A,0x7174,0x6B6E,0x6467,0x5E61,0x585B,0x5355,0x4D50,0x474A,0x4244,0x3C3F,0x373A,0x3234,0x2D2F,0x282B,0x2426,0x2022,0x1C1E,0x181A,0x1416,0x1113,0x0E10,0x0C0D,0x090A,0x0708,0x0506,0x0304,0x0203,0x0102,0x0001,0x0000	

; sum over n for { sin( x * n^2 ) / n^2 } with x from 0 to 2pi/257*256 (first dimension) and n in 1..16 (second dimension)

LEFT: .dw 0x0300,0x170D,0x211C,0x2826,0x312A,0x2D32,0x322E,0x4139,0x4743,0x4A4B,0x3F43,0x3D3F,0x3C3D,0x2E36,0x2628,0x2929,0x2726,0x352D,0x3C37,0x4142,0x3B3F,0x3435,0x3C37,0x4442,0x3E40,0x4642,0x4744,0x4A49,0x4E4E,0x5350,0x5A56,0x625E
      .dw 0x7669,0x9689,0xA19D,0xA9A5,0xAFAC,0xB1B1,0xB6B5,0xBBB8,0xBDB9,0xBFC1,0xBDBB,0xC8C3,0xCACB,0xC0C4,0xBDBE,0xC8C3,0xD2CA,0xD9D8,0xD6D6,0xD7D9,0xC9D1,0xC2C3,0xC0C2,0xBCC0,0xB4B5,0xBCB8,0xC6BE,0xD1CD,0xCDD2,0xD5CE,0xD9D7,0xE3DE
      .dw 0xF2E8,0xFFFC,0xFCFE,0xFBFA,0xF6F9,0xF8F8,0xEEF5,0xE8E9,0xECE8,0xF2F1,0xF6F2,0xFDF9,0xF2FA,0xE8EC,0xDCE2,0xDFDE,0xDDDD,0xCAD5,0xBDC2,0xB8BB,0xA4AE,0x999E,0x8A91,0x8488,0x8382,0x8B86,0x968F,0x9799,0x868F,0x8A86,0x8487,0x8485
      .dw 0x8182,0x7E80,0x7B7D,0x7B7A,0x7578,0x7979,0x6870,0x6966,0x7470,0x7C79,0x7B7D,0x7577,0x666E,0x5B61,0x4751,0x4244,0x353D,0x222A,0x2022,0x2321,0x171D,0x0D13,0x0205,0x0906,0x0D0D,0x130E,0x1717,0x1116,0x070A,0x0907,0x0406,0x0305

; sin( x ) + ( (index+1) mod 32 ) / 128 with x from 0 to 2pi/257*256 anf index from 0 to 255

DOWN: .dw 0x0201,0x0403,0x0706,0x0908,0x0C0B,0x100E,0x1311,0x1715,0x1B19,0x1F1D,0x2321,0x2826,0x2D2A,0x3230,0x3735,0x212C,0x2623,0x2C29,0x322F,0x3935,0x3F3C,0x4642,0x4C49,0x5350,0x5A57,0x615E,0x6865,0x6F6C,0x7773,0x7E7A,0x8582,0x707B
      .dw 0x7874,0x7F7B,0x8683,0x8D8A,0x9591,0x9C98,0xA39F,0xAAA6,0xB1AD,0xB8B4,0xBEBB,0xC5C2,0xCBC8,0xD2CE,0xD8D5,0xC1CC,0xC7C4,0xCCC9,0xD2CF,0xD7D4,0xDBD9,0xE0DE,0xE4E2,0xE9E7,0xEDEB,0xF0EE,0xF4F2,0xF7F5,0xFAF8,0xFCFB,0xFEFD,0xE4F1
      .dw 0xE6E5,0xE7E7,0xE9E8,0xEAE9,0xEAEA,0xEBEA,0xEBEB,0xEBEB,0xEAEB,0xEAEA,0xE9E9,0xE8E8,0xE7E7,0xE5E6,0xE3E4,0xC5D4,0xC3C4,0xC0C2,0xBEBF,0xBBBD,0xB8BA,0xB5B7,0xB2B4,0xAFB1,0xACAD,0xA8AA,0xA5A7,0xA1A3,0x9D9F,0x9A9C,0x9698,0x7686
      .dw 0x7274,0x6E70,0x6A6C,0x6769,0x6365,0x5F61,0x5C5E,0x585A,0x5557,0x5253,0x4F50,0x4C4D,0x494A,0x4647,0x4345,0x2534,0x2223,0x2021,0x1F1F,0x1D1E,0x1C1C,0x1A1B,0x1A1A,0x1919,0x1919,0x1818,0x1818,0x1919,0x1919,0x1A1A,0x1C1B,0x010E

; (sin( x ) + cos( x*3 )/7 with x from 0 to 2pi/257*256 

RGHT: .dw 0x0000,0x0101,0x0201,0x0303,0x0504,0x0605,0x0807,0x0909,0x0B0A,0x0D0C,0x0E0D,0x100F,0x1110,0x1212,0x1313,0x1414,0x1515,0x1616,0x1717,0x1818,0x1A19,0x1B1A,0x1C1B,0x1E1D,0x201F,0x2221,0x2523,0x2826,0x2B29,0x2F2D,0x3331,0x3836
      .dw 0x3E3B,0x4441,0x4A47,0x514E,0x5855,0x605C,0x6964,0x716D,0x7A75,0x837E,0x8C87,0x9591,0x9E9A,0xA7A3,0xB0AC,0xB9B5,0xC1BD,0xC9C5,0xD1CD,0xD8D4,0xDEDB,0xE4E1,0xEAE7,0xEFEC,0xF3F1,0xF6F4,0xF9F8,0xFBFA,0xFDFC,0xFEFE,0xFFFF,0xFFFF
      .dw 0xFFFF,0xFEFF,0xFDFE,0xFCFD,0xFBFB,0xF9FA,0xF8F9,0xF6F7,0xF4F5,0xF3F4,0xF1F2,0xF0F1,0xEEEF,0xEDEE,0xECED,0xEBEB,0xEAEA,0xE9E9,0xE8E8,0xE7E7,0xE6E6,0xE5E5,0xE3E4,0xE2E2,0xE0E1,0xDEDF,0xDBDC,0xD8DA,0xD5D7,0xD1D3,0xCDCF,0xC8CA
      .dw 0xC3C5,0xBDC0,0xB7BA,0xB0B3,0xA8AC,0xA1A5,0x999D,0x9094,0x878C,0x7E83,0x757A,0x6C71,0x6368,0x5A5E,0x5155,0x484D,0x4044,0x383C,0x3034,0x292C,0x2225,0x1C1F,0x1719,0x1214,0x0D0F,0x0A0B,0x0708,0x0405,0x0203,0x0102,0x0001,0x0000

BACK: .dw 0x0000,0x0000,0x0101,0x0202,0x0303,0x0504,0x0706,0x0908,0x0C0A,0x0E0D,0x1110,0x1413,0x1816,0x1C1A,0x201E,0x2422,0x2826,0x2D2B,0x322F,0x3734,0x3C3A,0x423F,0x4744,0x4D4A,0x5350,0x5855,0x5E5B,0x6461,0x6B67,0x716E,0x7774,0x7D7A
      .dw 0x8380,0x8A87,0x908D,0x9693,0x9C99,0xA29F,0xA8A5,0xAEAB,0xB4B1,0xB9B7,0xBFBC,0xC4C1,0xC9C7,0xCECC,0xD3D1,0xD8D5,0xDCDA,0xE0DE,0xE4E2,0xE8E6,0xEBEA,0xEFED,0xF1F0,0xF4F3,0xF7F5,0xF9F8,0xFAFA,0xFCFB,0xFDFD,0xFEFE,0xFFFE,0xFFFF
      .dw 0xFFFF,0xFFFF,0xFEFE,0xFDFE,0xFCFD,0xFAFB,0xF9FA,0xF7F8,0xF4F5,0xF1F3,0xEFF0,0xEBED,0xE8EA,0xE4E6,0xE0E2,0xDCDE,0xD8DA,0xD3D5,0xCED1,0xC9CC,0xC4C7,0xBFC1,0xB9BC,0xB4B7,0xAEB1,0xA8AB,0xA2A5,0x9C9F,0x9699,0x9093,0x8A8D,0x8387
      .dw 0x7D80,0x777A,0x7174,0x6B6E,0x6467,0x5E61,0x585B,0x5355,0x4D50,0x474A,0x4244,0x3C3F,0x373A,0x3234,0x2D2F,0x282B,0x2426,0x2022,0x1C1E,0x181A,0x1416,0x1113,0x0E10,0x0C0D,0x090A,0x0708,0x0506,0x0304,0x0203,0x0102,0x0001,0x0000

FRNT: .dw 0x0000,0x0000,0x0101,0x0202,0x0303,0x0504,0x0706,0x0908,0x0C0A,0x0E0D,0x1110,0x1413,0x1816,0x1C1A,0x201E,0x2422,0x2826,0x2D2B,0x322F,0x3734,0x3C3A,0x423F,0x4744,0x4D4A,0x5350,0x5855,0x5E5B,0x6461,0x6B67,0x716E,0x7774,0x7D7A
      .dw 0x8380,0x8A87,0x908D,0x9693,0x9C99,0xA29F,0xA8A5,0xAEAB,0xB4B1,0xB9B7,0xBFBC,0xC4C1,0xC9C7,0xCECC,0xD3D1,0xD8D5,0xDCDA,0xE0DE,0xE4E2,0xE8E6,0xEBEA,0xEFED,0xF1F0,0xF4F3,0xF7F5,0xF9F8,0xFAFA,0xFCFB,0xFDFD,0xFEFE,0xFFFE,0xFFFF
      .dw 0xFFFF,0xFFFF,0xFEFE,0xFDFE,0xFCFD,0xFAFB,0xF9FA,0xF7F8,0xF4F5,0xF1F3,0xEFF0,0xEBED,0xE8EA,0xE4E6,0xE0E2,0xDCDE,0xD8DA,0xD3D5,0xCED1,0xC9CC,0xC4C7,0xBFC1,0xB9BC,0xB4B7,0xAEB1,0xA8AB,0xA2A5,0x9C9F,0x9699,0x9093,0x8A8D,0x8387
      .dw 0x7D80,0x777A,0x7174,0x6B6E,0x6467,0x5E61,0x585B,0x5355,0x4D50,0x474A,0x4244,0x3C3F,0x373A,0x3234,0x2D2F,0x282B,0x2426,0x2022,0x1C1E,0x181A,0x1416,0x1113,0x0E10,0x0C0D,0x090A,0x0708,0x0506,0x0304,0x0203,0x0102,0x0001,0x0000
