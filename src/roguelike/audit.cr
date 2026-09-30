require "../roguelike"

module Roguelike
  # What is wrong with a dug floor, and how it is shaped.
  #
  # Everything here reads the squares of a `Floor` and nothing else, so it
  # judges a floor however it was made. `Generator` digs again when
  # `.faults` finds anything.
  #
  # Two words recur. A square is open when it is not rock. A square is part
  # of a room when it lies inside some block of three by three open squares.
  # The smallest room is four by three, so every square of a room is roomy
  # and a corridor one square wide never is.
  module Audit
    # The smallest room there is, across and down.
    LEAST = {4, 3}

    # How long two corridors have to run side by side to count as a pair.
    ALONGSIDE = 3

    # Everything wrong with *floor*. Empty for a sound one.
    #
    # *rooms*, when a caller has them, adds two checks: no room is smaller
    # than `LEAST`, and the staircases are in different rooms.
    def self.faults(floor : Floor, rooms : Array(Area)? = nil) : Array(String)
      found = [] of String
      open = open_squares floor

      staircases floor, found
      unreached floor, open, found
      hanging floor, found
      buried floor, found
      dead_ends floor, open, roomy_squares(floor, open), found
      sized rooms, floor, found if rooms

      found
    end

    # How many loops the open squares of *floor* make.
    #
    # One loop for each body of rock that no edge of the floor touches. A
    # walk with one hand on the wall goes round such a body and never sees
    # what is on the far side of it.
    #
    # *least* counts only the bodies of at least that many squares. A body
    # of one or two squares is where two corridors cross or a corridor runs
    # along a room, and a walk round it barely leaves the wall it was on.
    def self.loops(floor : Floor, least : Int32 = 1) : Int32
      seen = Set({Int32, Int32}).new
      count = 0

      floor.each do |column, row, tile|
        next unless tile.terrain.rock?
        next if seen.includes?({column, row})

        edge = false
        size = 0
        flood({column, row}, seen, diagonal: true) do |spot|
          next false unless floor.contains? spot[0], spot[1]
          next false unless floor.terrain(spot[0], spot[1]).rock?

          edge = true if edge?(floor, spot)
          size += 1
          true
        end
        count += 1 unless edge || size < least
      end

      count
    end

    # How many times two corridors run side by side for `ALONGSIDE` squares
    # or more.
    #
    # A corridor is a square of stone floor or a door that is not part of a
    # room. Two corridors side by side make a strip two wide, and each strip
    # counts once however long it is.
    def self.alongside(floor : Floor) : Int32
      roomy = roomy_squares floor, open_squares(floor)
      hall = Set({Int32, Int32}).new
      floor.each do |column, row, tile|
        next unless tile.terrain.stone_floor? || tile.terrain.door?
        next if roomy.includes?({column, row})

        hall << {column, row}
      end

      paired = Set({Int32, Int32}).new
      hall.each do |spot|
        { {ALONGSIDE, 2}, {2, ALONGSIDE} }.each do |shape|
          next unless block?(hall, spot, shape[0], shape[1])

          (0...shape[0]).each do |across|
            (0...shape[1]).each { |down| paired << {spot[0] + across, spot[1] + down} }
          end
        end
      end

      strips = 0
      seen = Set({Int32, Int32}).new
      paired.each do |spot|
        next if seen.includes? spot

        strips += 1
        flood(spot, seen, diagonal: false) { |near| paired.includes? near }
      end

      strips
    end

    # Every open square of *floor*.
    def self.open_squares(floor : Floor) : Set({Int32, Int32})
      found = Set({Int32, Int32}).new
      floor.each { |column, row, tile| found << {column, row} unless tile.terrain.rock? }
      found
    end

    # Every square of *floor* that lies inside a block of three by three
    # open squares.
    def self.roomy_squares(floor : Floor, open : Set({Int32, Int32})) : Set({Int32, Int32})
      found = Set({Int32, Int32}).new
      open.each do |corner|
        next unless block? open, corner, 3, 3

        (0...3).each do |across|
          (0...3).each { |down| found << {corner[0] + across, corner[1] + down} }
        end
      end
      found
    end

    # One up staircase and one down staircase.
    private def self.staircases(floor : Floor, found : Array(String)) : Nil
      ups = 0
      downs = 0
      floor.each do |_column, _row, tile|
        ups += 1 if tile.terrain.stairs_up?
        downs += 1 if tile.terrain.stairs_down?
      end

      found << "#{ups} up staircases" unless ups == 1
      found << "#{downs} down staircases" unless downs == 1
    end

    # Every open square reachable from the up staircase.
    #
    # A shut door is crossed, because walking into one opens it. The down
    # staircase is open, so this reaches it from both ends.
    private def self.unreached(floor : Floor, open : Set({Int32, Int32}),
                               found : Array(String)) : Nil
      up = floor.find Terrain::StairsUp
      return unless up

      reached = Set({Int32, Int32}).new
      flood(up, reached, diagonal: true) { |spot| open.includes? spot }
      missed = open.size - reached.size
      return if missed.zero?

      first = (open - reached).min_by { |spot| {spot[1], spot[0]} }
      noun = missed == 1 ? "square" : "squares"
      found << "#{missed} #{noun} out of reach, one at #{first[0]},#{first[1]}"
    end

    # Every door has a way off it on two facing sides.
    private def self.hanging(floor : Floor, found : Array(String)) : Nil
      floor.each do |column, row, tile|
        next unless tile.terrain.door?

        facing = {Direction::East, Direction::North}.any? do |direction|
          ahead = direction.from column, row
          behind = direction.opposite.from column, row
          open?(floor, ahead) && open?(floor, behind)
        end
        found << "a door hanging from nothing at #{column},#{row}" unless facing
      end
    end

    # Nothing stands, lies or hangs inside rock.
    private def self.buried(floor : Floor, found : Array(String)) : Nil
      floor.each_monster do |column, row, _creature|
        found << "a creature in rock at #{column},#{row}" unless open?(floor, {column, row})
      end

      floor.each_pile do |column, row, _pile|
        found << "a pile in rock at #{column},#{row}" unless open?(floor, {column, row})
      end

      floor.each_fixture do |column, row, _fitting|
        found << "a fixture in rock at #{column},#{row}" unless open?(floor, {column, row})
      end
    end

    # No corridor stops short of anywhere.
    #
    # A corridor square with one way off it or none is the end of a length
    # that leads nowhere. A cave's natural ends are dirt, and are left alone.
    private def self.dead_ends(floor : Floor, open : Set({Int32, Int32}),
                               roomy : Set({Int32, Int32}),
                               found : Array(String)) : Nil
      floor.each do |column, row, tile|
        next unless tile.terrain.stone_floor?
        next if roomy.includes?({column, row})

        ways = Direction.values.count do |direction|
          next false if direction.diagonal?

          open.includes? direction.from(column, row)
        end
        found << "a corridor ending nowhere at #{column},#{row}" if ways < 2
      end
    end

    # No room is smaller than `LEAST`, and the staircases are in different
    # rooms.
    private def self.sized(rooms : Array(Area), floor : Floor, found : Array(String)) : Nil
      rooms.each do |room|
        next if room.columns >= LEAST[0] && room.rows >= LEAST[1]

        found << "a room of #{room.columns} by #{room.rows} at #{room.x},#{room.y}"
      end

      up = floor.find Terrain::StairsUp
      down = floor.find Terrain::StairsDown
      return unless up && down

      shared = rooms.find { |room| room.holds?(up[0], up[1]) && room.holds?(down[0], down[1]) }
      found << "both staircases in the room at #{shared.x},#{shared.y}" if shared
    end

    # Whether *spot* is on *floor* and open.
    private def self.open?(floor : Floor, spot : {Int32, Int32}) : Bool
      floor.contains?(spot[0], spot[1]) && !floor.terrain(spot[0], spot[1]).rock?
    end

    # Whether *spot* is on the outermost ring of *floor*.
    private def self.edge?(floor : Floor, spot : {Int32, Int32}) : Bool
      spot[0].zero? || spot[1].zero? ||
        spot[0] == floor.columns - 1 || spot[1] == floor.rows - 1
    end

    # Whether every square of the block *columns* by *rows* whose top left
    # is *corner* is in *squares*.
    private def self.block?(squares : Set({Int32, Int32}), corner : {Int32, Int32},
                            columns : Int32, rows : Int32) : Bool
      (0...columns).all? do |across|
        (0...rows).all? { |down| squares.includes?({corner[0] + across, corner[1] + down}) }
      end
    end

    # Adds to *seen* every square joined to *from* through squares the block
    # accepts.
    private def self.flood(from : {Int32, Int32}, seen : Set({Int32, Int32}),
                           diagonal : Bool, & : {Int32, Int32} -> Bool) : Nil
      return unless yield from

      seen << from
      queue = [from]

      while spot = queue.pop?
        Direction.values.each do |direction|
          next if direction.diagonal? && !diagonal

          near = direction.from spot[0], spot[1]
          next if seen.includes? near
          next unless yield near

          seen << near
          queue << near
        end
      end
    end
  end
end
