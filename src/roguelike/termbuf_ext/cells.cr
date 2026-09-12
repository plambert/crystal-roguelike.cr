require "termbuf-widgets"

# Extraction candidate: `TermBuf::Widgets::Cells` and
# `TermBuf::Widgets::CellGrid`, for termbuf-widgets.cr.
#
# Everything in the widget catalogue draws text in rows. `VirtualList` is one
# item per screen row and `Table` is columns of text; nothing there is a 2D
# addressable field of glyphs with a window over it. A dungeon map wants one,
# and so does a minimap, a hex board, a Life grid, a chip layout and a tile
# editor — the viewport arithmetic, the camera, the mouse translation and the
# `Scrolls` wiring are the same every time.
#
# Written in `TermBuf::Widgets` rather than in `Roguelike` so that extracting
# it is a file move with no edits. What is still to settle before it goes:
#
# * Whether `#on_draw` should hand over a view per cell, as it does here, or
#   answer a glyph and a style. A view is the more general of the two and
#   matches `VirtualList#on_draw`; a glyph would allocate nothing.
# * Whether `Cells` should be able to say its extent has changed, the way
#   `Rows#size` is asked afresh every frame. It is asked afresh here, so a
#   source is free to answer differently; nothing has needed it yet.
module TermBuf::Widgets
  # Where a `CellGrid` gets what it shows.
  #
  # Three questions and no more: how wide the field is, how tall, and what is
  # at *x*, *y*. A window showing eight hundred cells of a million asks eight
  # hundred times, which is what lets it show a level nobody would hold twice.
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
  # This is `Rows` with two axes, and the same idea: the source is asked, and
  # what it is asked about is what is on the screen.
  abstract class Cells(T)
    # Cells across.
    abstract def columns : Int32

    # Cells down.
    abstract def rows : Int32

    # What is at *x*, *y*. Only ever asked about a cell that is showing.
    abstract def cell(x : Int32, y : Int32) : T

    # Both extents at once, which is the shape `Scrolls#content_size` wants.
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

    # Rows of cells as a source, the outer array being the rows.
    #
    # Every row has to be the same length, because a field with a ragged edge
    # has no answer for what is past the end of a short one.
    def self.of(grid : Array(Array(T))) : Cells(T)
      Held(T).new grid
    end

    # A block as a source, for a field that is computed rather than held.
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

    # Cells answered by a block, which is what a field too large to hold looks
    # like.
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
