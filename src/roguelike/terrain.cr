module Roguelike
  # Everything one kind of terrain is.
  #
  # *mark* is the character a floor file writes for this terrain. A save file
  # writes the same character. *mark* is part of the file format. Changing one
  # changes every floor file and every save file already written.
  #
  # This record sits beside `Terrain`. A Crystal enum body takes members and
  # methods. It takes neither type definitions nor constants.
  record TerrainKind,
    mark : Char,
    label : String,
    description : String,
    blocks_move : Bool,
    blocks_sight : Bool

  # What one square of a floor is made of.
  #
  # The three rocks behave alike. A player tells them apart by color. They
  # are separate members because what a wall is made of will matter later.
  # Digging will differ by rock. Sound through a wall will differ by rock. A
  # floor generator will pick a rock by depth.
  #
  # No member here carries a glyph or a style. `Ui::Palette` holds both. A
  # theme changes that table. A spec reads a floor with no terminal open.
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

    # Which terrain a floor file's *mark* names.
    #
    # This method raises on an unknown character. An unknown character is a
    # mistake in a floor file. A character that became floor instead would be
    # a hole in a wall. Nobody could find that hole by reading the file.
    def self.from_mark(mark : Char) : Terrain
      found = from_mark? mark
      return found if found

      raise ArgumentError.new "no terrain is written #{mark.inspect}"
    end

    # :ditto: Answers `nil` instead of raising.
    def self.from_mark?(mark : Char) : Terrain?
      Terrains::MARKS[mark]?
    end

    # What this terrain is. Every method below reads one field of it.
    def kind : TerrainKind
      Terrains::KINDS[self]
    end

    # The character a floor file writes for this terrain.
    def mark : Char
      kind.mark
    end

    # What this terrain is called. For a message or a readout.
    def label : String
      kind.label
    end

    # A sentence about this terrain. For the examine pane.
    def description : String
      kind.description
    end

    # Whether no creature can walk through this terrain.
    def blocks_move? : Bool
      kind.blocks_move
    end

    # Whether no creature can see through this terrain.
    def blocks_sight? : Bool
      kind.blocks_sight
    end

    # Whether a creature can walk through this terrain.
    def passable? : Bool
      !blocks_move?
    end

    # Whether this terrain is one of the rocks a floor is cut out of.
    def rock? : Bool
      granite? || sandstone? || shale?
    end

    # Whether this terrain is a floor a creature can stand on.
    def floor? : Bool
      stone_floor? || dirt_floor?
    end

    # Whether this terrain is a door. Open or shut.
    def door? : Bool
      closed_door? || open_door?
    end

    # Whether this terrain is a staircase. Up or down.
    def stairs? : Bool
      stairs_up? || stairs_down?
    end
  end

  # The table behind `Terrain`. An enum body cannot hold these constants.
  module Terrains
    # The character a floor file writes for an empty square.
    #
    # A blank means granite. An editor that trims trailing whitespace then
    # cannot change a floor. A row shorter than the floor's width is solid
    # rock rather than an error.
    FILL = ' '

    KINDS = {
      Terrain::Granite    => TerrainKind.new('#', "granite", "hard gray rock", true, true),
      Terrain::Sandstone  => TerrainKind.new('=', "sandstone", "soft yellow rock", true, true),
      Terrain::Shale      => TerrainKind.new('%', "shale", "layered blue-gray rock", true, true),
      Terrain::StoneFloor => TerrainKind.new('.', "stone floor", "worn flagstones", false, false),
      Terrain::DirtFloor  => TerrainKind.new(',', "dirt floor", "packed earth", false, false),
      Terrain::ClosedDoor => TerrainKind.new('+', "closed door", "a shut wooden door", true, true),
      Terrain::OpenDoor   => TerrainKind.new('\'', "open door", "a doorway standing open", false, false),
      Terrain::StairsUp   => TerrainKind.new('<', "staircase up", "a staircase leading up", false, false),
      Terrain::StairsDown => TerrainKind.new('>', "staircase down", "a staircase leading down", false, false),
    }

    # The character a floor file writes for a square that glows on its own.
    #
    # This is not a terrain. It is a stone floor with a light in it, and
    # `Floor.parse` splits it into the two. A magically lit room is written
    # with these.
    GLOW = '*'

    # How brightly a square written `GLOW` glows.
    GLOW_LIGHT = 2

    # Every character a floor file may hold.
    MARKS = begin
      table = {} of Char => Terrain
      KINDS.each { |terrain, kind| table[kind.mark] = terrain }
      table[FILL] = Terrain::Granite
      table
    end
  end
end
