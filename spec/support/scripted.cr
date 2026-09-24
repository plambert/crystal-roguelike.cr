# A run played from a seed and a written list of moves, with its fingerprint
# taken at every turn.
#
# The cross-process half of `spec/roguelike/fingerprint_spec.cr` plays the
# same runs in a second program. The moves and the loops that play them are
# here rather than in two files that can differ.
module Scripted
  # The moves one scripted run takes.
  #
  # A digit is `Roguelike::Direction.new` of it, so `0` is east and the rest
  # run anticlockwise from there. A dot is a turn spent standing still. A
  # move into rock takes no turn. That is a state a run reaches, so it is in
  # the list.
  MOVES = "00006622.4444660022.6644.00."

  # How many turns the bot is given.
  #
  # It is long enough to open a door, meet a creature and trade blows with
  # it. Every turn costs a fingerprint of a floor about a hundred kilobytes
  # wide, so this is one run rather than a trial.
  TURNS = 50

  # The fingerprint before the first of *moves* and after each of them.
  def self.walked(seed : UInt64, moves : String = MOVES) : Array(String)
    game = Roguelike::Game.dug Roguelike::Rng.new(seed)
    found = [game.fingerprint]

    moves.each_char do |move|
      if move == '.'
        game.wait
      else
        game.step Roguelike::Direction.new(move - '0')
      end

      found << game.fingerprint
    end

    found
  end

  # The fingerprint before, and after each turn `Trial::Bot` plays on *seed*.
  #
  # The bot fights, drinks, picks things up and takes stairs, so this walks
  # far more of the state than a list of steps does. It plays by a rule and
  # draws from the seed, so it plays the same way every time.
  def self.played(seed : UInt64, turns : Int32 = TURNS) : Array(String)
    bot = Roguelike::Trial::Bot.new seed
    found = [bot.game.fingerprint]

    turns.times do
      break if bot.game.over?

      bot.turn
      found << bot.game.fingerprint
    end

    found
  end
end
