# How the CPU players work

## Basic variables

First, calculate a few variables:

- **Target angle**: What's the target angle to the next wicket?
- **Lead point gap**: If we're in 1st place, how far ahead are we? If not in 1st, how far behind 1st place are we?
- **Wrong side**: Are we on the wrong side of the next wicket?
- **Easy shot**: Are close to the next wicket, and not shooting at an extreme angle?
- **Clear shot**: Are there any other balls nearby?
- **Target blocked**: Is there a wicket post blocking our path to the center of the next wicket?

## Determining actual target for next wicket

First, determine which wicket/pole we're targeting - normally it's the next one, but if we're in a position where we could shoot through the next wicket and get close to the one after, then use that 2nd wicket as the target instead. Right now there is no check beyond this, so the CPU will not deliberately target a pole through 2 wickets.

Then determine what point we actually want to aim for, for our target wicket/pole - do we target going through the wicket, or somewhere in front, or try to get the ball to stop just very slightly past the center of the wicket.

* If it's a pole, target beyond the wicket, so that we hit it with enough force to get a slight bounce off
* If we have an easy shot to score the wicket, then target beyond the wicket
* If we're on the wrong side, by a significant amount, target going just barely past the middle of the wicket, so that we're in a good position to hit it through next (or have someone else hit it through)
* If this wicket post is in the way, target in front of the wicket
* If we have 2 bonus shots, target in front of the wicket
* If none of the other conditions triggered, calculate a factor that determines the random chance for if we decide to play it safe and target slightly in front of the wicket, or try to go straight for the wicket. This is based on a few factors:
  - How easy a shot this is, in terms of angle & distance
  - How many extra shots do we have
  - What's the lead point gap? (Play safer if we're ahead, riskier if we're behind)
  - Riskier if there's another ball nearby, since they are likely going to want to hit our ball
  - Safer as "slop" value increases (more on this later)
* If we're targeting in front of the wicket, make sure our shot is not blocked by the wicket post, and if it is then target even further in front.

## Should we target a ball?

If we don't have bonus shots yet, or the path to the next wicket is blocked, then check if there's a good ball to target. We calculate a score for our target wicket and for each ball, and choose whichever has the lowest score.

For the wicket, the score is the distance to the wicket, although there are some things that can modify this: if our path to the wicket is blocked or we're on the wrong side, then increase the score quite a bit (to make it more likely that we target a ball). Or if we have an easy shot, decrease it (to make it more likely that we go for the wicket).

For each ball, the score is essentially how far the ball is away from us or the target (whichever is lower), plus how far out of the way it is off our path to the next wicket. We also add a penalty if the ball is on the wrong side of the target wicket (unless we are as well). If the ball is blocked by a wicket, then we ignore it entirely.

If we've selected another ball to target, then don't try to hit it head-on - adjust the target location just a smidge towards the next wicket, so that we get a more favorable bounce.

Finally, now that we've chosen a target, regardless of whether it's a wicket or a ball: check if the path to this target is blocked by another ball. If it is, target that ball instead. This check always happens, regardless of bonus shot status.

One possible improvement here: sometimes we could aim through a wicket, to try and target a ball on the other side. Right now there is no check to deliberately try this.

## Slop

The CPU logic can be very good in some circumstances - it can win before another player has a chance to shoot their first ball, which is no fun. So as a balancing mechanism, we add in a "slop" value: the higher the slop, the less accurate its shots.

Slop is based on a few different factors. It starts at zero, but can go up or down:

* Increase or decrease the base slop factor based on the gap to the leader
* Add 1 if there are no other balls nearby. This is because the CPU is very accurate when it has a clear shot, but its logic for dealing with other balls is not as goode way. So we add 1 if there are no other balls nearby.
* Subtract 1 if targeting another ball (not a wicket), and not in the lead.

If the slop value is at least +1, we add extra error to both power and angle. The amount of angle error depends on power - i.e. the CPU will make bigger mistakes with harder shots.

As the slop value increases, the CPU is also more likely to play it safe and target in front of the next wicket instead of trying to go through.
