require "../roguelike"

module Roguelike
  # How far sounds carry, and the map of where one went.
  #
  # A sound spreads from its square through the floor as it is, not through
  # what anybody believes about it. A wall stops it. A shut door lets it
  # through and takes `MUFFLE` squares off what is left. Every other square
  # costs one step, a diagonal one included, the way walking does.
  #
  # Every creature hears the same way for now. A creature hears a sound when
  # its square is within the sound's loudness along that map. A later pass
  # can give a species its own hearing by changing what `#hears?` compares.
  module Noise
    # What made a sound. Each member has its own loudness, in squares.
    enum Source
      # A swing in a fight, hit or miss.
      Blow

      # A missile hitting the floor or whatever stopped it.
      Landing

      # A bolt from a wand striking what it hit.
      Bolt

      # A swing at a shut door.
      DoorStruck

      # A door giving way.
      DoorBroken

      # A potion breaking. Nothing makes this yet.
      Shatter

      # A shout. Nothing makes this yet.
      Shout

      # How many squares of travel this sound has in it.
      def loudness : Int32
        case self
        in .blow?        then BLOW
        in .landing?     then LANDING
        in .bolt?        then BOLT
        in .door_struck? then DOOR_STRUCK
        in .door_broken? then DOOR_BROKEN
        in .shatter?     then SHATTER
        in .shout?       then SHOUT
        end
      end

      # What the character hears when they cannot see where it came from.
      def heard : String
        case self
        in .blow?        then "fighting"
        in .landing?     then "something land"
        in .bolt?        then "a crackle"
        in .door_struck? then "pounding"
        in .door_broken? then "a door crash"
        in .shatter?     then "glass break"
        in .shout?       then "a shout"
        end
      end

      # What this is called, for an event.
      def label : String
        to_s.underscore
      end
    end

    # How many squares of travel each source has.
    BLOW        =  8
    LANDING     =  5
    BOLT        =  6
    DOOR_STRUCK = 10
    DOOR_BROKEN = 14
    SHATTER     =  7
    SHOUT       = 16

    # The loudest any source is. The noise bar is out of this.
    LOUDEST = Source.values.max_of &.loudness

    # How many squares a shut door takes off a sound passing through it, on
    # top of the step onto the door itself.
    MUFFLE = 3

    # How the noise bar comes down after a sound.
    enum Decay
      # It falls `FADE` squares a turn from the loudest it reached.
      Fall

      # It shows the loudest sound of the character's last action, and
      # nothing after an action that made none.
      LastAction
    end

    # How the noise bar comes down. Change it here and build again.
    DECAY = Decay::Fall

    # How many squares the noise bar falls each turn under `Decay::Fall`.
    FADE = 1

    # How many turns pass before the character is told again of a sound of
    # the same kind they could not see.
    QUIET = 10

    # One sound.
    #
    # *at* is where it came from. *character* is where hearers then believe
    # the character is, or `nil` when the character has no part in it.
    # *creature* is the creature that made it, or `nil` for the character.
    record Sound, at : {Int32, Int32}, source : Source,
      character : {Int32, Int32}? = nil, creature : Monster? = nil do
      # Whether the character made it.
      def characters? : Bool
        creature.nil?
      end

      # How many squares of travel it has.
      def loudness : Int32
        source.loudness
      end
    end

    # Where a sound the character made went, for the screen.
    #
    # *reach* holds every square it got to with how many squares it had
    # traveled there. *loudness* is what it set out with. *carried* is the
    # furthest any square got.
    record Echo, at : {Int32, Int32}, loudness : Int32, reach : Descent do
      # How far the sound got.
      def carried : Int32
        most = 0
        reach.each { |_spot, away| most = away if away > most }
        most
      end
    end

    # A sound the character heard and could not see the source of.
    #
    # *mark* is where the map marks it: the last square in sight along the
    # line toward where it came from.
    record Heard, mark : {Int32, Int32}, source : Source

    # The map of how far a sound from *at* with *loudness* travels over
    # *floor*.
    #
    # A square holds the squares of travel the sound used getting there,
    # which is never more than *loudness*. A square the sound did not reach
    # is not in it. Walls are never in it. A shut door is, with `MUFFLE`
    # added.
    def self.spread(floor : Floor, at : {Int32, Int32}, loudness : Int32) : Descent
      found = {at => 0}
      waves = Array(Array({Int32, Int32})).new(loudness + 1) { [] of {Int32, Int32} }
      waves[0] << at

      (0..loudness).each do |away|
        waves[away].each do |spot|
          next unless found[spot]? == away

          Direction.values.each do |direction|
            wanted = direction.from spot[0], spot[1]
            cost = step wanted, floor
            next unless cost

            further = away + cost
            next if further > loudness
            held = found[wanted]?
            next if held && held <= further

            found[wanted] = further
            waves[further] << wanted
          end
        end
      end

      Descent.new at, found
    end

    # What one step onto *spot* costs a sound. `nil` for a square it cannot
    # enter.
    private def self.step(spot : {Int32, Int32}, floor : Floor) : Int32?
      tile = floor.tile? spot[0], spot[1]
      return unless tile

      terrain = tile.terrain
      return 1 + MUFFLE if terrain.closed_door?
      return unless terrain.passable?

      1
    end

    # Whether a creature on *spot* hears what *reach* holds.
    def self.hears?(reach : Descent, spot : {Int32, Int32}) : Bool
      !reach[spot].nil?
    end
  end
end
