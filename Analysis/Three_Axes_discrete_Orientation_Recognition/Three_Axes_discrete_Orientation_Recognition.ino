/*

 Three_Axes_discrete_Orientation_Recognition.ino
 ---------------------------------------------------------------------------
 begin                 : 2011-12-05
 copyright             : Copyright (C) 2011 by Manfred Morgner
 email                 : manfred.morgner@gmx.net
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *                                                                         *
 *   Free Software Foundation, Inc.,                                       *
 *   59 Temple Place Suite 330,                                            *
 *   Boston, MA  02111-1307, USA.                                          *
 *                                                                         *
 ***************************************************************************

3 Axes Accelerometer Input, 3 LED PWM Output, 1 Status flash output
 
 Reads an analog input on

   A5 for Z
   A6 for Y
   A7 for X

 Maps the result for each axis to a range from 0 to 2
 
 Uses the result to set the pulsewidth modulation (PWM) for

   D9  for Z
   D10 for Y
   D11 for X

 Based on "AnalogInOutSerial" from Arduino IDE Examples by Tom Igoe

   created 29 Dec. 2008
   modified 30 Aug 2011

3 Axes Sensore Response + mapped values from 0 to 10 as graphics

Y: 000   = 348 *****
   045 L = 294 *
   090 L = 278 
   135 L = 294 *
   180   = 348 *****
   045 R = 400 ********
   090 R = 420 **********
   135 R = 395 ********
   180   = 348 *****
   
X: 000   = 358 *****
   045 H = 304 **
   090 H = 281 
   135 H = 302 **
   180   = 355 *****
   045 V = 407 ********
   090 V = 427 **********
   135 V = 401 ********
   180   = 355 *****

Z: 000   = 428 **********
   045 O = 405 ********
   090 O = 353 *****
   135 O = 305 **
   180   = 283 
   045 U = 305 **
   090 U = 355 *****
   135 U = 400 ********
   000   = 428 **********

Valid posiiton recognisation based on mapping all 3 axes to the range 0 to 2

    Oben
      Links
        Unten
          Rechts
            Hinten
              Vorn
  | O L U R H V
--+------------
X | 1 1 1 1 0 2
Y | 1 0 1 2 1 1
Z | 2 1 0 1 1 1

Experimental mapping of all valid positions. The numeric converison bases on

   V = (X shl 4) OR (Y shl 2) OR Y

  | X Y Z  high--low dec   hex  grmn  engl  inst  instrument
--+--------------------------------------------------------------
O | 1 1 2  0001-0110  22  0x16  oben  uprt  xylw  xylophone wood
L | 1 0 1  0001-0001  17  0x11  lnks  left  orgn  organ key
U | 1 1 0  0001-0100  20  0x14  untn  down  xylm  xylophone metal
R | 1 2 1  0001-1001  25  0x19  rcht  rght  pian  piano
H | 0 1 1  0000-0101   5  0x05  hntn  back  drum  drum
V | 2 1 1  0010-0101  37  0x25  vorn  frnt  bell  bell


Experiental Measurement Results (from "Three_Axes_manual_Calibaration")

     min - max
     ---------
X => 279 - 428
Y => 275 - 426
Z => 278 - 430

 */

// Names for the pins

const int inAnalogZ = A5;  // Analog input pin attached to the Z axis
const int inAnalogY = A6;  // Analog input pin attached to the Y axis
const int inAnalogX = A7;  // Analog input pin attached to the X axis

const char outPwmZ  =  9;  // Analog output pin attached to the Z-LED
const char outPwmY  = 10;  // Analog output pin attached to the Y-LED
const char outPwmX  = 11;  // Analog output pin attached to the X-LED

const char outFlash =  8;  // flashlight to signal change of position

const char acOutput[3] = {0, 8, 255}; // light intensity map for 0,1,2

void setup()
  {
  // nothings to do so far
  }

/* =========================================================================

   Select response value 0, 1 or 2 for a given sensore value

   For the final product, inHigh and inLow has to be calibrated. The
   accelerometer sensor used for thi development show mainly even
   resonses for each axis. So we only need on pair of border values.

   ========================================================================= */
 
char ratio(int input)
  {
  const int inMin = 273; // Sensor minimal value (measured+manipulated)
  const int inMax = 432; // Sensor maximal value (measured+manipulated)
  
  // The sensor resonse is a sinus curve. We try to expand the middle part of
  // curve to stabelize the output mapping. Instead of using 1/3 of the
  // difference, we interprete only 20% of the caps of the sinus curve to find
  // out with sector of rotation we are in. We need a mapping _like_ this:
  //
  //     0° => 0
  //    90° => 1
  //   180° => 2
  //
  // For more information about acceleromater response see:
  //
  //   Accelerometer-Response.ods
  const char threshold = (inMax-inMin) / 5;
  if (input > inMax - threshold) return 2; // higher than max-(max-min)*20%
  if (input > inMin + threshold) return 1; // higher then min+(max-min)*20%
                                 return 0; // all values below
  }

/* =========================================================================

   The main loop reads input from 3 acceleromter axes and writes output
   mapped to 3 states to PWM D/A output to set 3 LEDs to 'off' 'half on'
   and 'on'. Also it falshes one LED to signalize a change from one valid
   position to another one.

   ========================================================================= */

void loop()
  {
  // valid end positions
  const  char uprt = 0x16;
  const  char left = 0x11;
  const  char down = 0x14;
  const  char rght = 0x19;
  const  char back = 0x05;
  const  char frnt = 0x25;

         char x, y, z;         // input values
         char xyzVector;       // current combined input values
  static char xyzLast  = uprt; // last valid position

  // three lines to do all the real work
  analogWrite(outPwmX, acOutput[x=ratio(analogRead(inAnalogX))]);
  analogWrite(outPwmY, acOutput[y=ratio(analogRead(inAnalogY))]);
  analogWrite(outPwmZ, acOutput[z=ratio(analogRead(inAnalogZ))]);

  // generates the combined vector from x,y,z input values 
  xyzVector = x << 4 | y << 2 | z;
  // test if current postion ist valid (test 1) and changed (test 2)
  char bChanged;
  switch (xyzVector)
    {
    // all valid positions
    case uprt: bChanged = xyzLast != uprt; break;
    case left: bChanged = xyzLast != left; break;
    case down: bChanged = xyzLast != down; break;
    case rght: bChanged = xyzLast != rght; break;
    case back: bChanged = xyzLast != back; break;
    case frnt: bChanged = xyzLast != frnt; break;
    // all invalid positions
    default:
       bChanged = false;
    }
  // we had a change from one valid position to another one
  if ( bChanged )
    {
    xyzLast = xyzVector;        // the new position becomes the old one
    analogWrite(outFlash, 255); // we do a short flashing of LED outFlash
    delay(100);
    analogWrite(outFlash, 0);
    }

  // wait 10 milliseconds before the next loop for the analog-to-digital
  // converter to settle after the last reading
  delay(10);
  } // end of main loop

