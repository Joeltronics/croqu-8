# Pico Croquet

License: Creative Commons BY-NC-SA 4.0

Includes some code by others (all CC4-BY-NC-SA):
* Some physics code from pico pool by nusan, BBS cart #21797
* pelogen_tri_low() from Pelogen by shiftalow, https://www.lexaloffle.com/bbs/?pid=75530#p

## Controls

* X + direction: Move camera
* Left/Right: Change shot angle
* O: Start shot, press a 2nd time to shoot

## Rules

* Start with 1 shot
* Gain 1 extra shot when scoring the next wicket or pole
* Gain 2 bonus shots on contact with another ball. These can only be claimed once per scored wicket/pole, and are cleared when scoring the next one. These are shown as outlined balls, and as empty outlines once used.
* Hitting another player's ball through their next wicket/pole counts for them, but does not award any bonus shots
* Wickets must be gone through in a certain direction to be scored.

## Tips

* Harder shots are a little bit less accurate (starting at 50% power, and gradually ramping up from there). If the power meter goes over 100% and turns red, then it will be much less accurate!
* Try to score more than 1 wicket/pole in one shot - this can give you several shots in a row!
* Sometimes it's better to target another player's ball for the bonus shots than to target the next wicket. It's not mean, it's all part of the game!
* Since bonus shots will be cleared on scoring the next wicket/pole, use these to line up your next shot
* After scoring, you can claim bonus shots again - even by targeting the same ball as before!
* Although you can't score a wicket by going though backwards, there's also no harm to doing so. Going through backwards might line you up for a great next shot - or can cause someone else to hit your ball through!

## TODO

End screen music?

Better title screen logo

High (low) scores?

Possibly some performance or token count optimizations (although so far, neither seems necessary)

AI improvements:

- Maybe add difficulty options?

"Maybe later" features:

- Different CPU difficulty settings
- Teams (pairs) mode
- Optional "Garden Croquet" layout & rules (the current is "Lawn Croquet")
