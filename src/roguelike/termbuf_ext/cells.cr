require "termbuf-widgets"

# Extraction candidate: `TermBuf::Widgets::Cells` and
# `TermBuf::Widgets::CellGrid`, for termbuf-widgets.cr.
#
# Every widget in the catalogue draws text in rows. `VirtualList` draws one
# item per screen row. `Table` draws columns of text. None of them is a 2D
# addressable field of glyphs with a window over it.
#
# A dungeon map needs one. So does a minimap. So does a hex board, a Life
# grid, a chip layout and a tile editor. Each of those needs the same viewport
# arithmetic, the same camera, the same mouse translation and the same
# `Scrolls` wiring.
#
# These types are written in `TermBuf::Widgets` rather than in `Roguelike`.
# Extracting them is then a file move with no edits.
#
# Two questions remain open:
#
# * Should `#on_draw` hand over a view per cell? It does that here. The other
#   option is to answer a glyph and a style. A view is the more general of the
#   two. It also matches `VirtualList#on_draw`. A glyph would allocate
#   nothing.
# * Should `Cells` be able to say its extent has changed? `Rows#size` is asked
#   afresh every frame. `Cells#columns` and `Cells#rows` are asked afresh too,
#   so a source may answer differently. Nothing has needed that yet.
module TermBuf::Widgets
  # Where a `CellGrid` gets what it shows.
  #
  # A source answers three questions. How wide is the field. How tall is it.
  # What is at *x*, *y*.
  #
  # A window showing eight hundred cells of a million asks eight hundred
  # times. The work is the size of the window. It is not the size of the
  # field.
  #
  #     class Level < TermBuf::Widgets::Cells(Tile)
  #       def columns : Int32
  #         @width
  #       end
  #
  #       def rows : Int32
  #         @height
  #       end
  #
  #       def cell(x : Int32, y : Int32) : Tile
  #         @tiles[y * @width + x]
  #       end
  #     end
  #
  # This is `Rows` with two axes. The idea is the same. The grid asks the
  # source. It asks only about what is on the screen.
  abstract class Cells(T)
    # Cells across.
    abstract def columns : Int32

    # Cells down.
    abstract def rows : Int32

    # What is at *x*, *y*. A grid asks only about a cell that is showing.
    abstract def cell(x : Int32, y : Int32) : T

    # The width and the height. `Scrolls#content_size` returns that shape.
    def size : {Int32, Int32}
      {columns, rows}
    end

    # Whether there is nothing to show.
    def empty? : Bool
      columns <= 0 || rows <= 0
    end

    # Whether *x*, *y* is inside the field.
    def contains?(x : Int32, y : Int32) : Bool
      0 <= x < columns && 0 <= y < rows
    end

    # Rows of cells as a source. The outer array holds the rows.
    #
    # Every row has to be the same length. A field with a ragged edge has no
    # answer for what is past the end of a short row.
    def self.of(grid : Array(Array(T))) : Cells(T)
      Held(T).new grid
    end

    # A block as a source. For a field a program computes rather than holds.
    def self.from(columns : Int32, rows : Int32,
                  fetch : Proc(Int32, Int32, T)) : Cells(T)
      Asked(T).new columns, rows, fetch
    end

    # Cells held as rows of rows.
    class Held(T) < Cells(T)
      # What is being shown.
      getter grid : Array(Array(T))

      def initialize(@grid : Array(Array(T)))
        widths = @grid.map(&.size).uniq!
        raise ArgumentError.new "rows are ragged: #{widths}" if widths.size > 1
      end

      def columns : Int32
        first = @grid.first?
        first ? first.size : 0
      end

      def rows : Int32
        @grid.size
      end

      def cell(x : Int32, y : Int32) : T
        @grid[y][x]
      end
    end

    # Cells answered by a block. A field too large to hold uses this.
    class Asked(T) < Cells(T)
      def initialize(@columns : Int32, @rows : Int32,
                     @fetch : Proc(Int32, Int32, T))
      end

      def columns : Int32
        @columns
      end

      def rows : Int32
        @rows
      end

      def cell(x : Int32, y : Int32) : T
        @fetch.call x, y
      end
    end
  end
end
