# Sounds

this is where imagination leafs me. THe place where real world sound will
be constructed to be played by MObject.

Because I'm no artist, I've no idea how a sound has to be compiled to left
positive impressions. So, my sounds are not realy for the air but of the
oszilloscope. Simply to differenciate sounds and amplitides to proof MObject
reacts to physical input.

If you have any sound you wish to share with me, here are the simple
requirements:

  * A sound is 257 samples long
  * The first sample has the value 0x00
  * The last sample is the same as the first one
  * One sample is a unsigned byte between 0x00 and 0xFF

If you wish to contribute a complete sound in program code manner you would
build the definition as text in 128 words in hexadecimal format and
intel(r) byte order. Like this:

  * decimal bytes....: 00, 02, 03, 16, 47, 212, ...
  * hexadecimal bytes: 00, 02, 03, 10, 2F, D4, ...
  * MObject words....: 0x0200,0x1003,0xD42F, ...
