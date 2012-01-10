/*

 Three_Axes_manual_Calibration.ino
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

 Based on "AnalogInOutSerial" from Arduino IDE Examples by Tom Igoe

 created 29 Dec. 2008
 modified 30 Aug 2011
 
 This is an experimental code to make calibartions and measurements with an
 3 axes accelerometer. Commenting is inherited from the original code. It's
 simple hacking code, provided only to complete development chain.
 
 There are no intensions to change anything in this code, it allready
 fullfilled it's mission.
 
 If you wish to see what it does - start it in your Arduino IDE and open
 your serial monitor. Then you will see...
 
 */

// Names to the IO pins
const int analogInPinZ = A5;  // Analog input pin that the potentiometer is attached to
const int analogInPinY = A6;  // Analog input pin that the potentiometer is attached to
const int analogInPinX = A7;  // Analog input pin that the potentiometer is attached to

const int analogOutPinZ = 11; // Analog output pin that the LED is attached to
const int analogOutPinY = 10; // Analog output pin that the LED is attached to
const int analogOutPinX =  9; // Analog output pin that the LED is attached to

// limits
const int inLow  = 280; // 270
const int inHigh = 425; // 441

// output levels
const int outLow  = 0;
const int outHigh = 3;

const int outFactor = 128 / (outHigh - outLow);

int sensorValue = 0;        // value read from the pot
int outputValue = 0;        // value output to the PWM (analog out)

int aMinMax[6];
const char aiX = 0;
const char aiY = 2;
const char aiZ = 4;

void setup()
  {
  // initialize serial communications at 9600 bps:
  Serial.begin(9600);
  
  // we autcalibrate 3 axes seperately - for experimental purpose
  // in the hope that this is not necessary in real life.
  aMinMax[aiX  ] = inLow;
  aMinMax[aiX+1] = inHigh;
  aMinMax[aiY  ] = inLow;
  aMinMax[aiY+1] = inHigh;
  aMinMax[aiZ  ] = inLow;
  aMinMax[aiZ+1] = inHigh;
  }

// map the sensor output into a range of 0 to 2
char ratio(int input, char index)
  {
  if (input < aMinMax[index  ]) aMinMax[index  ] = input;
  if (input > aMinMax[index+1]) aMinMax[index+1] = input;

  char jump = (aMinMax[index+1] - aMinMax[index])/3;
  int v = input - aMinMax[index];

  if (v > 2*jump) return 2;
  if (v >   jump) return 1;
  return 0;
  }

// read values, calculate results, output results
void loop()
  {
  // read the analog in value:
  sensorValue = analogRead(analogInPinX);            
  // map it to the range of the analog out:
  outputValue = ratio(sensorValue, aiX);
  // change the analog out value:
  analogWrite(analogOutPinX, outputValue*outFactor);           

  // print the results to the serial monitor:
  Serial.print("X sensor = " );
  Serial.print(sensorValue);
  Serial.print("\t output = ");
  Serial.print(outputValue);
  Serial.print("\t ia = " );
  Serial.print(aMinMax[aiX]);
  Serial.print(" - ");
  Serial.println(aMinMax[aiX+1]);


  // read the analog in value:
  sensorValue = analogRead(analogInPinY);            
  // map it to the range of the analog out:
  outputValue = ratio(sensorValue, aiY);
  // change the analog out value:
  analogWrite(analogOutPinY, outputValue*outFactor);           

  // print the results to the serial monitor:
  Serial.print("Y sensor = " );
  Serial.print(sensorValue);
  Serial.print("\t output = ");
  Serial.print(outputValue);
  Serial.print("\t ia = " );
  Serial.print(aMinMax[aiY]);
  Serial.print(" - ");
  Serial.println(aMinMax[aiY+1]);


  // read the analog in value:
  sensorValue = analogRead(analogInPinZ);            
  // map it to the range of the analog out:
  outputValue = ratio(sensorValue, aiZ);
  // change the analog out value:
  analogWrite(analogOutPinZ, outputValue*outFactor);

  // print the results to the serial monitor:
  Serial.print("Z sensor = " );
  Serial.print(sensorValue);
  Serial.print("\t output = ");
  Serial.print(outputValue);
  Serial.print("\t ia = " );
  Serial.print(aMinMax[aiZ]);
  Serial.print(" - ");
  Serial.println(aMinMax[aiZ+1]);


  // wait 10 milliseconds before the next loop
  // for the analog-to-digital converter to settle
  // after the last reading:
  delay(1000);
  // but we wait 1s to get a chance to read the results from the serial monitor!
  }
