module Roguelike
  # Everything one kind of terrain is, in one place.
  #
  # *mark* is the character a level file writes it as, which is also what a
  # save file holds. It is part of the file format, so changing one changes
  # every level and every save that has ever been written.
  #
  # It sits beside `Terrain` rather than inside it because an enum body in
  # Crystal takes members and methods, and neither type definitions nor
  # constants.
  record TerrainKind,
    mark : Char,
    label : String,
    description : String,
    blocks_move : Bool,
    blocks_sight : Bool

  # What one square of a level is made of.
  #
  # The three rocks behave alike and are told apart by eye. They are separate
  # members rather than one wall with a colour because what a wall is made of
  # is going to matter: digging, what a passage sounds like through it, and
  # what a level is built out of at a given depth.
  #
  # Nothing here knows what anything looks like. A glyph and a style are the
  # screen's business and live in `Ui::Palette`, so a theme can change them and
  # a spec can read a level without a terminal.
  enum Terrain
    Granite
    Sandstone
    Shale
    StoneFloor
    DirtFloor
    ClosedDoor
    OpenDoor
    StairsUp
    StairsDown

    # Which terrain a level file's *mark* names.
    #
    # Raises rather than guessing: a character nobody meant is a mistake in a
    # level, and one that quietly became floor would be a hole in a wall that
    # nobody could find by reading the file.
    def self.from_mark(mark : Char) : Terrain
      found = from_mark? mark
      return found if found

      raise ArgumentError.new "no terrain is written #{mark.inspect}"
    end

    # :ditto:, answering `nil` rather than raising.
    def self.from_mark?(mark : Char) : Terrain?
      Terrains::MARKS[mark]?
    end

    # What this terrain is, for everything that would otherwise want a `case`
    # of its own.
    def kind : TerrainKind
      Terrains::KINDS[self]
    end

    # The character a level file writes this as.
    def mark : Char
      kind.mark
    end

    # What it is called, for a message or a readout.
    def label : String
      kind.label
    end

    # A sentence about it, for the examine pane.
    def description : String
      kind.description
    end

    # Whether nothing can walk through it.
    def blocks_move? : Bool
      kind.blocks_move
    end

    # Whether nothing can see through it.
    def blocks_sight? : Bool
      kind.blocks_sight
    end

    # Whether something can walk through it, which is asked far more often
    # than its opposite.
    def passable? : Bool
      !blocks_move?
    end

    # Whether it is one of the rocks a level is cut out of.
    def rock? : Bool
      granite? || sandstone? || shale?
    end

    # Whether it is a floor somebody could stand on.
    def floor? : Bool
      stone_floor? || dirt_floor?
    end

    # Whether it is a door, open or shut.
    def door? : Bool
      closed_door? || open_door?
    end

    # Whether it is a staircase, up or down.
    def stairs? : Bool
      stairs_up? || stairs_down?
    end
  end

  # The table behind `Terrain`, which an enum body cannot hold itself.
  module Terrains
    # What a level file writes where there is nothing else to say.
    #
    # A blank is granite so that an editor trimming the trailing whitespace off
    # a line cannot change what a level is, and so that a row short of the
    # level's width is solid rock rather than an error.
    FILL = ' '

    KINDS = {
      Terrain::Granite    => TerrainKind.new('#', "granite", "hard grey rock", true, true),
      Terrain::Sandstone  => TerrainKind.new('=', "sandstone", "soft yellow rock", true, true),
      Terrain::Shale      => TerrainKind.new('%', "shale", "layered blue-grey rock", true, true),
      Terrain::StoneFloor => TerrainKind.new('.', "stone floor", "worn flagstones", false, false),
      Terrain::DirtFloor  => TerrainKind.new(',', "dirt floor", "packed earth", false, false),
      Terrain::ClosedDoor => TerrainKind.new('+', "closed door", "a shut wooden door", true, true),
      Terrain::OpenDoor   => TerrainKind.new('\'', "open door", "a doorway standing open", false, false),
      Terrain::StairsUp   => TerrainKind.new('<', "staircase up", "a staircase leading up", false, false),
      Terrain::StairsDown => TerrainKind.new('>', "staircase down", "a staircase leading down", false, false),
    }

    # Every character a level file may hold.
    MARKS = begin
      table = {} of Char => Terrain
      KINDS.each { |terrain, kind| table[kind.mark] = terrain }
      table[FILL] = Terrain::Granite
      table
    end
  end
end
