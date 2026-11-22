require "json"
require "../../src/crystal-roguelike"

# Puts an explore watch into a game, for specs of `Explore::Circling`.
#
# No pile can send explore round any more. A read up close moves the
# revision, and that starts the watch again. These give a game a watch that
# has already got as far as a spec needs, through a save and a load, so the
# rest of the game plays as it would after a real circle.
module Watching
  # *game* again, with *watch* as its explore watch.
  def self.holding(game : Roguelike::Game, watch : Roguelike::Explore::Circling) : Roguelike::Game
    saved = JSON.parse(game.to_json).as_h
    saved["circling"] = JSON.parse(watch.to_json)
    Roguelike::Game.from_json saved.to_json
  end

  # *game* again, with a watch that has given up where the character
  # stands, on the ground the game stands on now.
  def self.stuck(game : Roguelike::Game) : Roguelike::Game
    saved = JSON.parse game.to_json
    moves = saved["pack_moves"]?.try(&.as_i) || 0
    ground = Roguelike::Explore::Circling::Ground.new game.floor.id,
      game.knowledge.revision, moves
    watch = Roguelike::Explore::Circling.new
    watch.watch ground, game.player.at, 0_i64, game.turn
    watch.give_up game.player.at
    holding game, watch
  end
end
