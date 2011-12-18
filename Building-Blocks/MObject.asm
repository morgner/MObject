; MObject.asm
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

; ============================================================================================================
; Documentation
;
; 1) Expectations
;
; 1.1) MC: Atmel168 or Atmael328 or compatible models
;
; 1.2) Accelerometer ADXL335 connectd like this:
;
; X-axis  Y-axis  Y-axis
;   ADC7    ADC6    ADC5

; 1.3) 3 LEDs connected to PORTB like this:
;
; LED-0  LED-1  LED-2
;    B0     B1     B2

; ------------------------------------------------------------------------------------------------------------
; 2) Concept
;
; This is a part (building block) of an application embedded in an environment that requires a constant rate
; of timer interrupts to build a sound wave using 256 sample per sound. This means, the part tested here has to
; endure the same condition. Thats why the measurement is split into 3 cycles with status control to limit the
; amount of machine cycle to deal with the analog measurements for all 3 axes and postprocessing.
;
; Possibly, This measurement may walk alone and sound generation alone should be triggered by interrupts, but
; such mechanics inflict many problems by design. Possibly I will test this anyway. If MObject is free to deal
; with measurement of orientation, it may may do lot more things. Such as autocalibration, PWM control, multi-
; channel output, serial communicaiton and so on.
;
; For the moment, the current solution is the one to go with...

; ------------------------------------------------------------------------------------------------------------
;
;    V = (X shl 4) OR (Y shl 2) OR Y
;
;   | X Y Z  high--low dec   hex  grmn  engl  inst  instrument
; --+--------------------------------------------------------------
; O | 1 1 2  0001-0110  22  0x16  oben  uprt  xylw  xylophone wood
; L | 1 0 1  0001-0001  17  0x11  lnks  left  orgn  organ key
; U | 1 1 0  0001-0100  20  0x14  untn  down  xylm  xylophone metal
; R | 1 2 1  0001-1001  25  0x19  rcht  rght  pian  piano
; H | 0 1 1  0000-0101   5  0x05  hntn  back  drum  drum
; V | 2 1 1  0010-0101  37  0x25  vorn  frnt  bell  bell


; Arduino Nano 3.0 shipped with 168 and (later) 328
.DEVICE atmega328
;.DEVICE atmega168

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
;org ADCCaddr
;    rjmp    interrupt_adcmr_1  ; register 'interrupt_adcmr_1' as ADC measurement ready

; ============================================================================================================
; Definition Section

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
.def pSample     = r28   ; alias to YL, will be initialised by sound-to-RAM copy procedure (YL)
.def YH          = r29   ; Y high byte
.def Z           = r30   ; Z word
.def ZL          = r30   ; Z low byte
.def ZH          = r31   ; Z high byte

; ------------------------------------------------------------------------------------------------------------
; preconfiguration values for ADC

.equ Xaxis  = (1 << MUX2) | (1 << MUX1) | (1 << MUX0)                       ; X => ADC7
.equ Yaxis  = (1 << MUX2) | (1 << MUX1) | (0 << MUX0)                       ; Y => ADC6
.equ Zaxis  = (1 << MUX2) | (0 << MUX1) | (1 << MUX0)                       ; Z => ADC5
.equ Naxis  = (1 << MUX2) | (0 << MUX1) | (0 << MUX0)                       ; NO AXIS - Cycle Terminator

.equ AdcPrescale  = (1 << ADPS2) | (0 << ADPS1) | (0 << ADPS0)              ; Scale: 16 => 1MHz on 16MHz
.equ AdcConfig    = (1 << ADEN)  | (0 << ADATE) | (1 << ADIF) | (0 << ADIE) ; ADC Enable, Clear Interrupt Flag
.equ AdcMuxConfig = (1 << REFS0) | (1 << ADLAR) | (0 << MUX3)               ; REF=VCC, Left Aligned Result

; inMin     = 273 0x0111 Sensor minimal value (measured+manipulated)
; inMax     = 432 0x01B0 Sensor maximal value (measured+manipulated)
; dMinMax   = 159 0x009F Difference of min and max
; bTreshold =  31 0x001F 20% of dMinMax
; ignoren the lower 2 bits of the result, we go with 1/4 of the values shown
.equ cbMin        = 0x44                                ; 273/4 minimum value
.equ cbThresholdU = 0x20                                ; 128/4 upper threshold
.equ cbThresholdL = 0x07                                ;  31/4 lower threshold

; valid positions as x-y-z-value mix: (X shl 4) OR (Y shl 2) OR Y
; measured input to 'mapped bits': 
;   2 if input > max - threshold
;   1 if input > min + threshold
;   0 otherwise
.equ xyzUPRT      = 0x16                                ; upright
.equ xyzLEFT      = 0x11                                ; left side
.equ xyzDOWN      = 0x14                                ; down side
.equ xyzRGHT      = 0x19                                ; right side
.equ xyzBACK      = 0x05                                ; to back
.equ xyzFRNT      = 0x25                                ; to front

; logical orientations later used to select actions
.equ vecUPRT      = 0                                   ; 1 upright
.equ vecLEFT      = 1                                   ; 2 left side
.equ vecDOWN      = 2                                   ; 3 down side
.equ vecRGHT      = 3                                   ; 4 right side
.equ vecBACK      = 4                                   ; 5 to back
.equ vecFRNT      = 5                                   ; 6 to front

; other values
.def bTPBL        = r1                                  ; timer preset (low)
.def bTPBH        = r2                                  ; timer preset (high)
.def xyzLast      = r3                                  ; last seen xyz-combined byte
.def xyzNew       = r4                                  ; new calcualted xyz-combined byte
.def vecOrient    = r5                                  ; vector of orientation (0-5)
.def xyzChanged   = r6                                  ; accumulator for orientation change state
.def bCopyAccu    = r7                                  ; accumulator for copying bytes from FLASH to RAM
.def bSample      = r8                                  ; value of curent sample in sound

.def valNULL      = r16                                 ; simply a NULL
.def bTemp        = r17                                 ; a short sighted temporary value
.def bInput       = r18                                 ; see it as 'input accumulator'
.def bCurrentAxis = r19                                 ; STATUS:the axis the current measuremnt is running on


; ============================================================================================================
; Staring of the programm

     setup:
            cli                                         ; we don't wish to get interruptet - while setting up

; initialize named variables

            clr     valNULL                             ; valNULL has to become NULL
            clr     bSample                             ; no klick on startup

            ldi     bTemp,        vecUPRT               ; the asumed position at startup is upright
            mov     vecOrient,    bTemp                 ; if wrong - it will be corrected in ms

            ldi     bTemp,        xyzUPRT               ; if we wish to prevent unneccesary action
            mov     xyzLast,      bTemp                 ; we have to set the associated xyzLast value

            ldi     bTemp,        0x01                  ; 1   we pretent to had a change of orientaiton (which we
            mov     xyzChanged,   bTemp                 ; 1   had indeed) to ensure any side processing will execute

            ldi     bCurrentAxis, Xaxis                 ; 1   at the first measurement, we test axis X

            ldi     bTemp,        TPBL                  ; 1   timer preset (low)
            mov     bTPBL,        bTemp                 ; 1     preloading it optimizes ISR procedure
            ldi     bTemp,        TPBH                  ; 1   timer preset (high)
            mov     bTPBH,        bTemp                 ; 1     by reducing timer refload by 2 cycles

; initialize stak pointer

            ldi     bTemp,        low (RAMEND)          ; 1   initializing stack pointer
            out     SPL,          bTemp                 ; 1
            ldi     bTemp,        high(RAMEND)          ; 1
            out     SPH,          bTemp                 ; 1

; prepair timer interrupt

            ldi     bTemp,        0x00                  ; 1   set time1 to "no waveform generation & no compare match interrupt"
            sts     TCCR1A,       bTemp                 ; 2   
            ldi     bTemp,        0x01                  ; 1   set timer1 prescaler to 1
            sts     TCCR1B,       bTemp                 ; 2   
            ldi     bTemp,        0x02                  ; 1   set timer1 to overflow interrupt timer
            sts     TIMSK1,       bTemp                 ; 2

; define PORTC as ADC input

            out     DDRC,         valNULL               ; 1   set all pins to input mode

            ldi     bTemp,        0xFF                  ; 1   all pins
            out     ctlSound,     bTemp                 ; 1   set all pins to output mode for sound

; initialize destination/source address for RAM-sound starting by YL=0
            ldi     YL,           low (abSound)         ; 1   sound wave into RAM
            ldi     YH,           high(abSound)         ; 1
            cpse    YL,           valNULL               ; 1-3 is YL already NULL ?
            inc     YH                                  ; 1   no => we use the next higher adress with YL = 0

; define PORTB as output digital output

            ldi     bTemp,        0xFF                  ; 1   all pins
            out     DDRB,         bTemp                 ; 1   set output pins for PORTB

            sts     DIDR0,        valNULL               ; 2   no digital buffer for ADC input
            sts     ADCSRB,       valNULL               ; 2   default configuration
            ldi     bTemp,        AdcConfig | AdcPrescale ; 1
            sts     ADCSRA,       bTemp                 ; 2   out specific configutation

            ldi     bTemp,        AdcMuxConfig | Xaxis  ; 1
            sts     ADMUX,        bTemp                 ; 2   We start cycle with X axis; Multiplexer to X axis

            lds     bTemp,        ADCSRA                ; 2   3 lines instead of SBI
            ori     bTemp,        1 << ADSC | 1 << ADIF ; 1   start first measurement and ensure ADIF is cleard
            sts     ADCSRA,       bTemp                 ; 2   Start Measurement Now

; set timer for first interrupt

            sts     TCNT1L,       valNULL               ; 1 initial time setup. we are setting up, 
            sts     TCNT1H,       valNULL               ; 1 the first periode does no matter
            sei                                         ; 1 now we are ready to receive interrupts

; this is a kind of multi tasking window, we do something usefull an become interrupted if the timer calls
     forever:

     Yield_01:                                          ; copy current sound to RAM if orientation changed
            tst     xyzChanged                          ; 1   if orientation has not changed
            breq    Yield_02                            ; 1-2   we do nothings about it
            tst     pSample                             ; 1   we only change the sound if it will not click
            brne    Yield_02                            ; 1-2   otherwise we try later
            cli                                         ; 1   no interrupts, we are changing the world
            ldi     ZL,           low (awSoundFlash*2)  ; 1   sound address in FLASH
            ldi     ZH,           high(awSoundFlash*2)  ; 1   
            add     ZH,           vecOrient             ; 1   Z + 256*'orientation' to address the chosen sound
            clr     YL                                  ; 1   one times 0 to 0 makes 256 (sound bytes)
    CopyByte:                                           ; 256*7 = 1792 cycles = 0.112 ms
            lpm     bCopyAccu,    Z+                    ; 3   read next byte from FLASH
            st      Y,            bCopyAccu             ; 1   write this byte to RAM
            inc     YL                                  ; 1   one sample done
            brne    CopyByte                            ; 2-1 if not NULL we have to copy another one
            sei                                         ; 1   ok, done with the critical path
            clr     xyzChanged                          ; 1   ok, orientation WAS changed

    Yield_02:
            sei
            nop
            nop
            nop
            nop
            rjmp    forever

; ============================================================================================================
; this is the time critical path

     interrupt_timer_1:

; set timer for next interrupt

            sts     TCNT1L,       bTPBL                 ; 1 We have to set timer values each time
            sts     TCNT1H,       bTPBH                 ; 1 

; not to forget, we are in constante time frame, so we output the sample from the previous round

            lsr     bSample
            out     outSound,     bSample               ; 1   send sample to output

; until here, it was all about timing, but CLR will modify SREG!

            in      bTemp,        SREG                  ; 1   we have to save SREG for after
            push    bTemp                               ; 2   not cheap, but necessary!

            clr     bSample                             ; 1   we had it played, so we clear it off

            out     PORTB,        vecOrient             ; 1  show what we got (Orientation 0..6)

; check is measurement is finished

            cpse    xyzChanged,   valNULL               ; 1-3 do we have an unhandled orientation change pending?
            rjmp    NoAdcRead                           ; 2   orientation change not yet dealed with

            lds     bTemp,        ADCSRA                ; 2   Gather Axis Position And Select Next Axis?
            sbrc    bTemp,        ADSC                  ; 1-3 if ADSC in ADCSRA is ON, measurement is done
            rjmp    NoAdcRead                           ; 2   Measuremnet not yet finished

; yes it was, so we start processing the result

            lds     bInput,       ADCH                  ; 2   we ignore the L-Byte (=> bAxis = result/4) (see ADLAR bit)

;           sbi     ADCSRA,       ADIF                  ; 1   only on Atmega8 !
            ori     bTemp,        1 << ADIF             ; 1   we have to clear ADIF to proceed with ADCing
            sts     ADCSRA,       bTemp                 ; 2   

; map input to table range 0, 1 or 2

     MI2TR:
            subi    bInput,       cbMin                 ; 1   input - min to normalize input

            cpi     bInput,       cbThresholdU          ; 1   are we over the upper threshold?
            brcs    MI2TR_test_for_1                    ; 1-2 no, possibly, we have to return 1
            ldi     bInput,       2                     ; 1   we have to return 2
            rjmp    BuildOrientation                    ; 2
     MI2TR_test_for_1:
            cpi     bInput,       cbThresholdL          ; 1   are we over the lower threshold?
            brcs    MI2TR_return_0                      ; 1-2 no, we have to return 0
            ldi     bInput,       1                     ; 1   we have to return 1
            rjmp    BuildOrientation                    ; 2 
     MI2TR_return_0:
            ldi     bInput,       0                     ; 1 
            rjmp    AxisCombined                        ; 2   with 0, there is nothings to combine
     BuildOrientation:                                  ;     formula: xyNew = (X shl 4) OR (Y shl 2) OR Y
            cpi     bCurrentAxis, Zaxis                 ; 1   if this was Z
            breq    AxisCombine                         ; 1-2    we will not shift any bit
            cpi     bCurrentAxis, Yaxis                 ; 1   if this was not Y (it is X)
            breq    ShiftY                              ; 1      we will only shift 2 bits to left
     ShiftX:                                            ;     dummy lable, yust for understanding the code
            lsl     bInput                              ; 1   we have to shift X axis result 4 bits to the left
            lsl     bInput                              ; 1
     ShiftY:
            lsl     bInput                              ; 1   we have to shift Y axis result 2 bits o the left
            lsl     bInput                              ; 1
     AxisCombine:
            or      xyzNew,       bInput                ; 1   combine the last result to 'measured vector'

; new mapped/normalized bits in place inside xyzNew
     AxisCombined:
            dec     bCurrentAxis                        ; 1   7, 6, 5, but not 4 = 111, 110, 101, but not 100
            cpi     bCurrentAxis, Naxis                 ; 1   if we reached NO-AXIS we have completed a 3axes cycle
            breq    CyclusComplete                      ; 1-2   so we have to recognize what we are dealing with
            rjmp    AxisSelected                        ; 2     otherwise, we simply measure the next axis
     CyclusComplete:
            ori     bCurrentAxis, Xaxis                 ; 1   at first, after we finished this, we start with X axis

; all three axis were read, now we have to deal with the result

            cp      xyzNew,       xyzLast               ; 1   did orientation change ?
            breq    ResetBuffers                        ; 1-2 no - so we clean up

; here we found out, that the orientation had changed, but we don't know if the new orientation is valid
; we only accept a change of orientation if the new orientation is valid, so we have to filter for the result
; for validity.

            mov     bInput,       xyzNew                ; 1   cpi does not work with LOW REGISTERS

            ldi     bTemp,        vecUPRT               ; 1   if this is the new postion, we are UPRT
            cpi     bInput,       xyzUPRT               ; 1   is it the new position?
            breq    ValidOrientation                    ; 1-2   yes, so we accept it
            ldi     bTemp,        vecLEFT               ; 1   ...
            cpi     bInput,       xyzLEFT               ; 1   ...
            breq    ValidOrientation                    ; 1-2 ...
            ldi     bTemp,        vecDOWN               ; 1
            cpi     bInput,       xyzDOWN               ; 1
            breq    ValidOrientation                    ; 1-2
            ldi     bTemp,        vecRGHT               ; 1
            cpi     bInput,       xyzRGHT               ; 1
            breq    ValidOrientation                    ; 1-2
            ldi     bTemp,        vecBACK               ; 1
            cpi     bInput,       xyzBACK               ; 1
            breq    ValidOrientation                    ; 1-2
            ldi     bTemp,        vecFRNT               ; 1
            cpi     bInput,       xyzFRNT               ; 1
            breq    ValidOrientation                    ; 1-2 => 19 cycles to find out if and what

            rjmp    ResetBuffers                        ; 2   the orientation is not valid, we irgnoe it
     ValidOrientation:
            mov     vecOrient,    bTemp                 ; 1   the last assumed logical orientation was correct
            mov     xyzLast,      xyzNew                ; 1   the new orientation becomes the current one
            inc     xyzChanged                          ; 1   we remember: the orientation has changed

     ResetBuffers:
            clr     xyzNew                              ; 1   clear buffer for bit manipulaiton

; next axis for measurement ist set, now we start the next measurement

     AxisSelected:
            ldi     bTemp,        AdcMuxConfig          ; 1   initializing measurement for the nex axis
            or      bTemp,        bCurrentAxis          ; 1   this is the axis
            sts     ADMUX,        bTemp                 ; 1   MUX is now informed where and how to measure

;           sbi     ADCSRA,       ADSC                  ; 1   Start Measurement Now (on ATMEGA8)
            lds     bTemp,        ADCSRA                ; 2   we are on Atmega 328, more steps to do
            ori     bTemp,        1 << ADSC             ; 1   add the start flag to the ADCSRA value
            sts     ADCSRA,       bTemp                 ; 2   Start Measurement Now

            tst     xyzChanged                          ; 1   were orientation changed?
            breq    NoOutput                            ; 1-2 if not, we also will not change anything

     NoOutput:

     NoAdcRead:

     play:

; get the next sample but don't output because here, we hae no constant time frame anymore
; we do not use "ld bSample, Y+" because we don't want to increment YH!

            ld      bSample,      Y                     ; 1   we get the value, we use it later
            inc     pSample                             ; 1   next time, next sample (pSample is YL)

     interrupt_timer_1_end:

            pop     bTemp                               ; 2   restoring SREG for the interrupted process
            out     SREG,         bTemp                 ; 1   now we are clean again

            reti

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
