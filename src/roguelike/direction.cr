module Roguelike
  # One step on the eight-way grid.
  #
  # The members run anticlockwise from east. The opposite of a direction is
  # four steps round. `#opposite` is arithmetic. It needs no table.
  enum Direction
    East
    NorthEast
    North
    NorthWest
    West
    SouthWest
    South
    SouthEast

    # Columns this step moves. East is positive.
    def dx : Int32
      case self
      in .east?, .north_east?, .south_east? then 1
      in .west?, .north_west?, .south_west? then -1
      in .north?, .south?                   then 0
      end
    end

    # Rows this step moves. South is positive. A screen counts rows downward.
    # A floor stores rows in the same order it draws them.
    def dy : Int32
      case self
      in .north?, .north_east?, .north_west? then -1
      in .south?, .south_east?, .south_west? then 1
      in .east?, .west?                      then 0
      end
    end

    # Both offsets at once.
    def step : {Int32, Int32}
      {dx, dy}
    end

    # Where *x*, *y* is after this step.
    def from(x : Int32, y : Int32) : {Int32, Int32}
      {x + dx, y + dy}
    end

    # The direction back.
    def opposite : Direction
      Direction.new (value + 4) % 8
    end

    # Whether this step moves on both axes.
    def diagonal? : Bool
      dx != 0 && dy != 0
    end

    # What this direction is called. For a message.
    def label : String
      case self
      in .east?       then "east"
      in .north_east? then "north-east"
      in .north?      then "north"
      in .north_west? then "north-west"
      in .west?       then "west"
      in .south_west? then "south-west"
      in .south?      then "south"
      in .south_east? then "south-east"
      end
    end
  end
end
