# Pico Croquet

License: Creative Commons BY-NC-SA 4.0

Includes some code by others (all CC4-BY-NC-SA):
* Some physics code from pico pool by nusan, BBS cart #21797
* pelogen_tri_low() from Pelogen by shiftalow, https://www.lexaloffle.com/bbs/?pid=75530#p

## Controls

* X + direction: Move camera
* Left/Right: Change shot angle
* O: Start shot, press a 2nd time to shoot

If the power meter hits the top (goes red) then the shot will be less accurate

## Rules

* Start with 1 shot
* Gain 1 extra shot when scoring the next wicket or pole
* Gain 2 extra shots on contact with another ball. These can only be claimed once per scored wicket/pole, and are cleared when scoring the next wicket/pole. These are shown as outlined balls, and as empty outlines once used.
* Scoring a wicket/pole on someone else's turn counts, but does not award any bonus shots
* Wickets must be gone through in a certain direction to be scored (going through backwards does not count as anything)

## TODO

More sound effects

Possibly some performance or token count optimizations (although so far, neither seems necessary)

AI improvements:

- Maybe add difficulty options?

"Maybe later" features:

- Teams (pairs) mode
- Optional "Garden Croquet" layout & rules (the current is "Lawn Croquet")
