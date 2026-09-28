# Where `require "crystal-roguelike"` lands. It requires the whole game.
#
# The model comes first and stands on its own. What follows it draws a run in
# a terminal, and every file under `src/roguelike/ui/` requires this file
# rather than the model alone.
require "./roguelike"
require "./roguelike/ui"
require "./roguelike/session"
require "./roguelike/cli"
