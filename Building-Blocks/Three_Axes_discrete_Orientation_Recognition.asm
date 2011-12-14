; Three_Axes_discrete_Orientation_Recognition.asm
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


; with support from 
; http://www.mikrocontroller.net/articles/AVR-Tutorial:_ADC
; http://www.mikrocontroller.net/articles/Diskussion:AVR-Tutorial:_ADC

; and documentations from (not limited to)
; http://www.arduino.cc/
; http://www.protostack.com/blog/2011/02/analogue-to-digital-conversion-on-an-atmega168/
; http://www.rn-wissen.de/index.php/ADC_(Avr)
; http://www.atmel.com/dyn/resources/prod_documents/doc8025.pdf
; http://www.google.com
; ... many others ...

; ------------------------------------------------------------------------------------------------------------
; Atmega168/328 docu for analog input


; == ADCSRA (ADC Control and Status Register A)
;
; Bit : 7     6     5     4     3     2     1     0
; Name: ADEN  ADSC  ADATE ADIF  ADIE  ADPS2 ADPS1 ADPS0
; r/w : rw    rw    rw    rw    rw    rw    rw    rw
; init: 0     0     0     0     0     0     0     0

; 7 ADEN (ADC Enable)
; Activate/Stopp (1/2) ADC
; After ADEN ist set to 1 this first time (?), we should wait for 10ms (?)
;
; 6 ADSC (ADC Start Conversion)
; Start conversion (the flag stays on until the result is ready)
; The first start after ADCEN will do an initialisaton measurement before the first real measurement
;
; 5 ADATE (ADC Auto Trigger Enable)
; When this bit is written to one, Auto Triggering of the ADC is enabled. The ADC will start a conversion on a
; positive edge of the selected trigger signal. The trigger source is selected by setting the
; ADC Trigger Select bits, ADTS in ADCSRB
;
; 4 ADIF (ADC Interrupt Flag)
; Becomes 1 if result is ready, keeps 1 until
;   * The ISR came back (reti); Triggers an Interrupt if ADIE is ON
;   * 1 is written to it
; After a measurement without interrupt, we must clear ADIF
;
; 3 ADIE (ADC Interrupt Enable)
; Enables Interrupts for ADIF; ISR has to be regsitered at ISR table entry "????"
;
; 2 ADPS2 (ADC Prescaler Select Bit 2)
; 1 ADPS1 (ADC Prescaler Select Bit 1)
; 0 ADPS0 (ADC Prescaler Select Bit 0)
; Divisor to the MC frequency for the ADC frequency. The result should lay between 50 and 1000kHz
;
; ADPS2  ADPS1  ADPS0  Faktor  MC=8MHz  MC=16MHz
; -----  -----  -----  ------  -------  --------
;   0      0      0       2
;   0      0      1       2
;   0      1      0       4
;   0      1      1       8   1.000kHz              (1 << ADPS1) | (1 << ADPS0)
; * 1      0      0      16     500kHz  1.000kHz    (1 << ADPS2)
;   1      0      1      32     250kHz    500kHz
;   1      1      0      64     125kHz    250kHz
;   1      1      1     128      62kHz    125kHz
;
; The duration of a measurement is assumed to be 13 ADC cycles


; == ADCSRB (ADC Control and Status Register B)
;
; Bit : 7     6     5     4     3     2     1     0
; Name: ----  ACME  ----  ----  ----  ADTS2 ADTS1 ADTS0
; r/w : r     rw    r     r     r     rw    rw    rw
; init: 0     0     0     0     0     0     0     0
;
; 2 ADTS2 (ADC Trigger Source Select Bit 2)
; 1 ADTS1 (ADC Trigger Source Select Bit 1)
; 0 ADTS0 (ADC Trigger Source Select Bit 0)
;
; ADTS2  ADTS1  ADTS0  Trigger Source
; -----  -----  -----  ------------------------------
;   0      0      0    Free Running Mode
;   0      0      1    Analog Comparator
;   0      1      0    External Interrupt Request 0
;   0      1      1    Timer/Counter0 Compare Match A
;   1      0      0    Timer/Counter0 Overflow
;   1      0      1    Timer/Counter1 Compare Match B
;   1      1      0    Timer/Counter1 Overflow
;   1      1      1    Timer/Counter1 Capture Event


; == ADMUX (ADC Multiplexer Selection Register)
;
; Bit : 7     6     5     4     3     2     1     0
; Name: REFS1 REFS0 ADLAR ----  MUX3  MUX2  MUX1  MUX0
; r/w : rw    rw    rw    r     rw    rw    rw    rw
; init: 0     0     0     0     0     0     0     0
;
; 6,7 REFS0, REFS1 (Reference Selection Bits 0,1)
;
; * the external capacitor is not strictly necessary, but it will stabalize
;   the measurement
;
; REFS1  REFS0   Reference Source
; -----  -----   -----------------------------------------------------------
;    0      0    AREF, internal Vref deactivated
;    0      1    AVCC  (with external capacitor on AREF*)
;    1      0    # reserved
;    1      1    Internal 2,56V reference (with external capacitor on AREF*)
;
; 5 ADLAR (ADC Left Adjust Result)
; Adjusts the result bits inside the result bytes this way:
;
; ADLAR to 0:
;              ADCH                                   ADCL
;   +---+---+---+---+---+---+---+---+   +---+---+---+---+---+---+---+---+
;   |   |   |   |   |   |   | 9 | 8 |   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
;   +---+---+---+---+---+---+---+---+   +---+---+---+---+---+---+---+---+
;
; ADLAR to 1:
;              ADCH                                   ADCL
;   +---+---+---+---+---+---+---+---+   +---+---+---+---+---+---+---+---+
;   | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 |   | 1 | 0 |   |   |   |   |   |   |
;   +---+---+---+---+---+---+---+---+   +---+---+---+---+---+---+---+---+
;
; MUX3-MUX0 (Analog Channel and Gain Selection)
;
; MUX3  MUX2  MUX1  MUX0   Pin/Fn
; ----  ----  ----  ----   ------
;   0     0     0     0    PC0
;   0     0     0     1    PC1
;   0     0     1     0    PC2
;   0     0     1     1    PC3
;   0     1     0     0    PC4
;   0     1     0     1    PC5
;   0     1     1     0    PC6
;   0     1     1     1    PC7


; == DIDR0  (Digital Input Disable Register 0)
; 1 to a bit disables the corresponding digital input buffer (reduces energy consumption)
; 
; Bit : 7     6     5     4     3     2     1     0
; Name: ----  ----  ADC4D ADC4D ADC3D ADC2D ADC1D ADC0D
; r/w : r     r     rw    rw    rw    rw    rw    rw
; init: 0     0     0     0     0     0     0     0


; == ADCL / ADCH
; Result Registers Low/High
; Reading ADCL blocks AHCH until ADCH is read too


; ============================================================================================================
; MObject docu
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

.dseg

.cseg

.org 0x0000
     rjmp    setup              ; register 'setup' as Programm Start Routine
.org OVF1addr
     rjmp    interrupt_timer_1  ; register 'interrupt_timer_1' as Timer1 Overflow Routine
;org ADCCaddr
;    rjmp    interrupt_adcmr_1  ; register 'interrupt_adcmr_1' as ADC measurement ready

; ------------------------------------------------------------------------------------------------------------
;  A4 = 440 Hz
; Interrupt Generator has to be adjusted to 256*'A5' = 112640 Hz => 142 cycles to do what's necessary
; 2 byte timing, here with value 0xFF72 (142) for 112640 Hz on 16MHz MC
.equ    TPBH     = 0xff  ; timer preset (high)
.equ    TPBL     = 0x7F  ; timer preset (low)

; ------------------------------------------------------------------------------------------------------------
; preconfiguration values for ADC

.equ Xaxis  = (1 << MUX2) | (1 << MUX1) | (1 << MUX0)   ; X => ADC7
.equ Yaxis  = (1 << MUX2) | (1 << MUX1) | (0 << MUX0)   ; Y => ADC6
.equ Zaxis  = (1 << MUX2) | (0 << MUX1) | (1 << MUX0)   ; Z => ADC5
.equ Naxis  = (1 << MUX2) | (0 << MUX1) | (0 << MUX0)   ; NO AXIS - Cycle Terminator

.equ AdcPrescale  = (1 << ADPS2)                        ; ADC prescaler to 16 => 1MHz on 16MHz Atmega
                                                        ; implies: | (0 << ADPS1) | (0 << ADPS0)

.equ AdcConfig    = (1 << ADEN)                         ; ADC config
                                                        ; implies: | (0 << ADATE) | (0 << ADIF)  | (0 << ADIE)

.equ AdcMuxConfig = (1 << REFS0) | (1 << ADLAR)         ; MUX configuration: REF=VCC, Left Aligned Result
                                                        ; implies:  | (0 << MUX3)

; inMin     = 273 0x0111 Sensor minimal value (measured+manipulated)
; inMax     = 432 0x01B0 Sensor maximal value (measured+manipulated)
; dMinMax   = 159 0x009F Difference of min and max
; bTreshold = 31  0x001F 20% of dMinMax
; ignoren the lower 2 bits of the result, we go with 1/4 of the values shown
.equ cbMin        = 0x44                                ; 273/4 minimum value
.equ cbThresholdU = 0x21                                ; 128/4 upper threshold
.equ cbThresholdL = 0x06                                ;  31/4 lower threshold

; valid positions as x-y-z-value mix: (X shl 4) OR (Y shl 2) OR Y
; input to 'mapped bits': 
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

.def valNULL      = r16                                 ; simply a NULL
.def bTemp        = r17                                 ; a short sighted temporary value
.def bInput       = r18                                 ; see it as 'input accumulator'
.def bCurrentAxis = r19                                 ; STATUS:the axis the current measuremnt is running on


; ============================================================================================================
; Staring of the programm

     setup:
            cli

; initialize named variables

            clr     valNULL                             ; we don't wish to get interruptet - while setting up

            ldi     bTemp,        vecUPRT               ; the asumed position at startup is upright
            mov     vecOrient,    bTemp                 ; if wrong - it will be corrected in ms

            ldi     bTemp,        xyzUPRT               ; if we wish to prevent unneccesary action
            mov     xyzLast,      bTemp                 ; we have to set the associated xyzLast value

            ldi     bCurrentAxis, Xaxis                 ; at the first measurement, we test axis X

            ldi     bTemp,        TPBL                  ; timer preset (low)
            mov     bTPBL,        bTemp                 ; 
            ldi     bTemp,        TPBH                  ; timer preset (high)
            mov     bTPBH,        bTemp                 ; 

; initialize stak pointer

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

; define PORTC as ADC input

            out     DDRC,         valNULL               ; set input pins

; define PORTB as output digital output

            ldi     bTemp,        0xFF                  ; all pins to pullup / all pins to outtput
            out     DDRB,         bTemp                 ; set output pins for PORTB

            sts     DIDR0,        valNULL               ; no digital buffer for ADC input
            sts     ADCSRB,       valNULL               ; default configuration
            ldi     bTemp,        AdcConfig | AdcPrescale
            sts     ADCSRA,       bTemp                 ; out specific configutation

            ldi     bTemp,        AdcMuxConfig | Xaxis
            sts     ADMUX,        bTemp                 ; We start cycle with X axis; Multiplexer to X axis

            lds     bTemp,        ADCSRA                ; 3 lines instead of SBI
            ori     bTemp,        ADSC | ADIF           ; ensure ADIF is cleard in each case
            sts     ADCSRA,       bTemp                 ; Start Measurement Now

; set timer for first interrupt

            sts     TCNT1L,       valNULL               ; 1 initial time setup. we are setting up, 
            sts     TCNT1H,       valNULL               ; 1 the first periode does no matter
            sei                                         ; 1 now we are ready to receive interrupts

     forever:
            rjmp    forever

; ============================================================================================================
; this is the time critical path

     interrupt_timer_1:

; set timer for next interrupt

            sts     TCNT1L,       bTPBL                 ; 1 We have to set timer values each time
            sts     TCNT1H,       bTPBH                 ; 1 

            out     PORTB,        vecOrient             ; 1  show what we got (Orientation 0..6)

; check is measurement is finished

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
            breq    ValidOrientation                    ; 1-2

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

; this is a possible point to change something regarding to the change of orientation

            clr     xyzChanged                          ; 1  ok, orientation WAS changed

     NoOutput:

     NoAdcRead:
;           make music / prepair next sample

            reti
