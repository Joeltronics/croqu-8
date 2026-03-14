# How the CPU players work

## Basic variables

First, calculate a few variables:

- **Target angle**: What's the target angle to the next wicket?
- **Lead point gap**: If we're in 1st place, how far ahead are we? If not in 1st, how far behind 1st place are we?
- **Wrong side**: Are we on the wrong side of the next wicket?
- **Easy shot**: Are close to the next wicket, and not shooting at an extreme angle?
- **Clear shot**: Are there any other balls nearby?
- **Target blocked**: Is there a wicket post blocking our path to the next wicket?

## Determining target point for next wicket

First, determine which wicket/pole we're targeting - normally it's the next one, but if we're in a position where we could shoot through the next wicket and get close to the one after, then use that 2nd wicket as the target instead.

Then determine what point we actually want to aim for, for our target wicket/pole - do we target going right through the wicket, or play it safe and target somewhere in front to set up the next shot?

There are a few conditions that we check which can force it to choose one or the other, like if something is in the way or if we have 2 bonus shots (in which case we might as well try and play it safe, because we'll lose the bonus shots when trying to go through anyway).

If none of these conditions triggered, then calculate a "play it safe factor" to determine the random chance for whether we decide to target slightly in front of the wicket, or try to go straight for the wicket. This is based on a few factors, like how easy the shot is, are there other balls nearby, etc?

Finally, if we're targeting in front of the wicket, make sure our shot is not blocked by the wicket post - if it is, then target even further in front.

## Should we target a ball?

If we don't have bonus shots yet, or the path to the next wicket is blocked, then check if there's a good ball to target. We calculate a score for our target wicket and for each ball, and choose whichever has the lowest score. For the wicket, the score is the distance to the wicket, with a few modifiers on top of this to skew the odds based on certain conditions. For each ball, the score is essentially how out of the way this ball would be on the way to our next target.

Then there's one more check: regardless of if we're targeting another wicket or ball, check if the path to this target is blocked by another ball. If it is, target that ball instead. This can lead to targeting another ball even after we've already taken bonus shots.

## Slop

The CPU logic can be very good in some circumstances - it can win before another player has a chance to shoot their first ball, which is no fun. So as a balancing mechanism, we add in a "slop" value: the higher the slop, the less accurate its shots.

* Increase or decrease the base slop factor based on the gap to the leader
* Add 1 if there are no other balls nearby. This is because the CPU is very accurate when it has a clear shot, but its logic for dealing with other balls is not as good.
* Subtract 1 if targeting another ball (not a wicket), and not in the lead.

If the slop value is at least +1, we add extra error to both power and angle. The amount of angle error depends on power - i.e. the CPU will make bigger mistakes with harder shots.

The slop value also affects the "play it safe factor" - the more slop, the more likely the CPU is to play it safe and target in front of the next wicket.

## Difficulties

Initially there was only 1 difficulty. This later became "hard", and I added 2 easier and 1 harder difficulties.

Difficulty affects a few things:

* Slop factor
  - At easy/medium, add 1
  - At pro, slop is always 0
* How likely the CPU is to try and target another ball (i.e. the base score needed for a ball vs wicket)
  - Easy is quite a bit less likely
  - Medium is slightly less likely
* How likely the CPU is to play it safe and target in front of the next wicket
  - Easy difficulty is twice as likely
  - When shooting through a wicket to target the next one, easy & medium will always play it safe
* Some of the logic for looking past the next wicket to target the one after is disabled at easier difficulties
  - At easy, we don't try this at all
  - At medium, we do but then don't try to target another ball through the wicket (unless a ball is blocking our path)
* At pro, the CPU hits other balls extra hard
