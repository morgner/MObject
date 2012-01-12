# MObject

## What it is

MObject is a physical, 'intelligent' object to be used in music and art.

It responds to handling and action, both are yet to be defined.

There are different sensors - currently a 3 axes accelerometer - and different
output devices - currently 5 LEDs and one digital-to-analog converter - to do
the experiments and feasibility studies.

Currently the LEDs are used as 'debugging display' and the DAC is used to
output sounds depending on the position of the object in space.

 * If you're in a hurry and in search of the *real code* goto 'Building-Blocks'.
 * If you whish to see some *C/C++ code* for your research, goto 'Analysis'.

## STATE OF THE ART

Currently the state of the art of MObject is to change the sound produced to
one out of six depending on it's orientation in the world. Next two steps are

 1. [done] Change the hardware to ATmega 8 (to speed it up)
 1. Implement sound-fading to make a more natural sounding object
 1. Hit/stroke/slap-detection to finally make the object usable
 1. Design an intelligent PCB to integrate MObject into objects
 1. Develop inter-object-communication to provide swarm 'intelligence'

After these steps state of the art will be 'inteligent swarming musical objects'
which will be a starting point for a cultural revolution never seen before ;-)
