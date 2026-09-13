require "./floor"
require "./line"

module Roguelike
  # Why a thing thrown or fired stopped where it did.
  enum Landing
    # It arrived at the square it was aimed at with nothing standing there.
    Reached

    # It ran into a creature.
    Struck

    # It ran into something it could not cross.
    Blocked

    # It ran out of reach.
    Spent
  end

  # Where a thing thrown or fired goes, and where it stops.
  #
  # The line is `Line`'s, which sight and light also walk, so a shot at
  # something visible crosses the squares the sight of it crossed.
  #
  # A flight stops at the first creature it meets, at the first square it
  # cannot cross, or when its reach runs out. Whichever comes first.
  #
  # This struct changes nothing. `Game` reads one to find out what the missile
  # met. `Play` reads the same one to draw the line while a person aims.
  struct Flight
    # Where it was let go from.
    getter from : {Int32, Int32}

    # The square it was aimed at.
    getter target : {Int32, Int32}

    # Every square it crossed, in order, the last one included. The square it
    # was let go from is not here.
    getter path : Array({Int32, Int32})

    # Why it stopped.
    getter landing : Landing

    def initialize(@from : {Int32, Int32}, @target : {Int32, Int32},
                   @path : Array({Int32, Int32}), @landing : Landing)
    end

    # Where it ended up. The square it was let go from when it went nowhere.
    def at : {Int32, Int32}
      @path.last? || @from
    end

    # Whether it got as far as it was aimed.
    def clear? : Bool
      at == @target
    end

    # Whether it ran into a creature.
    def struck? : Bool
      @landing.struck?
    end

    # How many squares it crossed.
    def distance : Int32
      @path.size
    end

    # Where a thing let go at *from* and aimed at *to* stops.
    #
    # *reach* is how many squares it can cross. A reach of zero leaves it on
    # the square it was let go from.
    def self.toward(floor : Floor, from : {Int32, Int32}, to : {Int32, Int32},
                    reach : Int32) : Flight
      path = [] of {Int32, Int32}
      landing = Landing::Reached
      started = false

      Line.walk from, to do |spot|
        # The line starts on the square the missile was let go from. Nothing
        # is in the way there, whatever is standing on it.
        unless started
          started = true
          next
        end

        if path.size >= reach
          landing = Landing::Spent
          break
        end

        unless floor.contains?(spot[0], spot[1]) && floor.passable?(spot[0], spot[1])
          landing = Landing::Blocked
          break
        end

        path << spot

        if floor.monster? spot[0], spot[1]
          landing = Landing::Struck
          break
        end
      end

      new from, to, path, landing
    end

    def to_s(io : IO) : Nil
      io << "Flight(" << @from[0] << ',' << @from[1]
      io << " -> " << at[0] << ',' << at[1]
      io << ' ' << @landing << ')'
    end
  end
end
