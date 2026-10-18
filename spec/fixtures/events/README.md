# Events fixture

`run.events.jsonl` is 25 lines of the events file of one headless run, unzipped. The run is seed 2,
played by a scratch program that takes random legal actions, prefers a fight or a staircase, and
was moved onto the staircase down once to reach the second floor. It ends in a death.

The lines are a selection, in their order in the file: the header, the opening `stats` line, a
potion drunk, two pickups, the arrival on floor 2 and its `stats` line, a throw, a fight with a
slime, a fight with two goblin warriors, the death, the last `stats` line and the footer. Each line
is as the game wrote it.

The dashboard reads this file in its specs. `spec/roguelike/events_spec.cr` checks that every
event line in it still parses as an event the game knows.
