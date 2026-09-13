module Roguelike::Ui
  # A floor, as something a `CellGrid` can draw.
  #
  # This adapter exists so that `Floor` needs no reference to the widget
  # layer. A floor is the model. A `Cells` is what a window over one asks. The
  # game reads and writes the first. Only the screen holds the second.
  class FloorCells < Widgets::Cells(Tile)
    # Which floor is being shown.
    #
    # Assigning another floor shows that one instead. Walking down a staircase
    # will do that.
    property floor : Floor

    def initialize(@floor : Floor)
    end

    def columns : Int32
      @floor.columns
    end

    def rows : Int32
      @floor.rows
    end

    def cell(x : Int32, y : Int32) : Tile
      @floor.tile x, y
    end
  end

  # The window a floor is played in.
  #
  # This class holds the `CellGrid` and the camera over it. It also holds the
  # rule for drawing one tile. Every change to where the window points goes
  # through here.
  class MapPane
    # What the grid asks for its cells.
    getter cells : FloorCells

    # The widget itself. A caller puts it in a tree.
    getter grid : Widgets::CellGrid(Tile)

    # Cells kept between the followed square and the edge of the window. The
    # camera does not move while the square is further in than this.
    property margin : Int32 = 6

    # Squares kept clear around the character when a modal box covers part of
    # the window.
    property avoid_margin : Int32 = 3

    # What the character can see from where they stand. `nil` draws every
    # square, which is what a pane with no game behind it does.
    #
    # A square outside this draws as `Palette::UNSEEN`. Nothing on it draws
    # either. A mark is something standing on a square, and a square the
    # character cannot see shows nothing standing on it.
    property sight : Vision? = nil

    # What the character remembers of this floor. `nil` remembers nothing, so
    # a square out of sight draws blank.
    #
    # A remembered square draws what it looked like when it was last seen,
    # dimmed. The floor goes on changing after the character looks away and
    # what is drawn does not.
    property knowledge : Knowledge? = nil

    # How the flames waver. `nil` holds them still, which is what a pane with
    # no game behind it does and what a spec that is not about flicker wants.
    property flicker : Flicker? = nil

    # The square the examine cursor is on. `nil` when there is no cursor.
    #
    # The cursor draws over whatever is on the square. It does not replace it.
    # The cursor marks its square. It leaves the glyph on that square
    # readable.
    property cursor : {Int32, Int32}? = nil

    # What is standing on a square. It draws over the terrain. It is not
    # written into the floor.
    #
    # The character goes here now. Monsters and dropped items go here later.
    # Whatever owns the game state fills this table. A pane draws a floor. It
    # holds nothing about the creatures on it.
    getter marks : Hash({Int32, Int32}, Look) = {} of {Int32, Int32} => Look

    # Squares offered as an answer to a question.
    #
    # Each keeps its own glyph and its own colour. Only the background
    # changes. A person choosing between four doors has to see which door is
    # which.
    getter highlights : Set({Int32, Int32}) = Set({Int32, Int32}).new

    # Squares a shot would cross, and the colour each is drawn on.
    #
    # The line is one colour and the square the shot stops on is another. A
    # person aiming has to see where the line runs and where it ends.
    getter flight : Hash({Int32, Int32}, TermBuf::Color) = {} of {Int32, Int32} => TermBuf::Color

    def initialize(floor : Floor)
      @cells = FloorCells.new floor
      @grid = Widgets::CellGrid.new @cells
      @grid.background = Palette::GROUND_STYLE
      @grid.on_draw = ->(view : TermBuf::View, x : Int32, y : Int32, tile : Tile) do
        look = looked_at x, y, tile

        style = look.style
        style = style.bg Palette::OFFERED if @highlights.includes?({x, y})

        aimed = @flight[{x, y}]?
        style = style.bg aimed if aimed

        here = @cursor
        style = style.reverse if here && here[0] == x && here[1] == y

        view.write_char 0, 0, look.glyph, style
        nil
      end
    end

    # How *x*, *y* draws.
    #
    # A square in sight draws what is there now, shaded by how much light is
    # on it. A square out of sight draws what it looked like when it was last
    # seen, at the bottom of the ramp. A square nobody has ever seen draws
    # blank.
    private def looked_at(x : Int32, y : Int32, tile : Tile) : Look
      shape = silhouette x, y
      return shape if shape
      return remembered x, y unless seen? x, y

      level = light x, y
      kind = @sight.try &.light_kind(x, y)

      # A lit square never falls to the step a remembered one draws at,
      # however many flames gutter at once. Two things a person tells apart
      # at a glance stay apart.
      step = (Palette.step(level) + wavering(x, y))
        .clamp Palette::REMEMBERED + 1, Palette::STEPS - 1

      Palette.shaded live(x, y, tile), step, kind
    end

    # How far the flames reaching *x*, *y* have shifted the step it draws at.
    private def wavering(x : Int32, y : Int32) : Int32
      found = @flicker
      return 0 unless found

      found.shift @sight.try(&.flames_at(x, y)) || Lighting::NO_FLAMES
    end

    # A creature standing on an unlit square the character has a line to.
    #
    # It is seen as a shape against light behind it, so it draws at the
    # dimmest step there is light at. `nil` when no creature is there, when
    # the square is lit, or when there is nothing behind it to show against.
    #
    # The shape is what is drawn, not the creature. `Palette.shape` answers a
    # glyph for the size and one colour for every species, because a letter
    # and a colour each name a species and a shape against light names none.
    #
    # A shape wavers with the flames lighting the square behind it. Its own
    # square has no light on it and so has no flames reaching it.
    private def silhouette(x : Int32, y : Int32) : Look?
      return if seen? x, y

      creature = floor.monster x, y
      return unless creature

      found = @sight
      return unless found

      behind = found.backlight floor, x, y
      return unless behind

      Palette.shaded Palette.shape(creature.species.size), shape_step(behind)
    end

    # Which step of the ramp a shape lit from *behind* draws at.
    #
    # `Palette::SHAPE_STEP` while the flame holds still, and up to
    # `Palette::SHAPE_WAVER` above it while the flame flares. A guttering
    # flame leaves the shape where it is, because a step below `SHAPE_STEP`
    # is the step a remembered square draws at.
    #
    # A shape against a magically lit room does not move. Nothing is burning
    # there, so `Flicker#shift` answers zero.
    private def shape_step(behind : {Int32, Int32}) : Int32
      base = Palette::SHAPE_STEP

      (base + wavering(behind[0], behind[1])).clamp base, base + Palette::SHAPE_WAVER
    end

    # What is on *x*, *y* now, topmost first.
    #
    # A mark is something standing on the square. A creature draws over what
    # is lying there, an item draws over whatever is fitted to the square, and
    # a fixture draws over the terrain.
    private def live(x : Int32, y : Int32, tile : Tile) : Look
      mark = @marks[{x, y}]?
      return mark if mark

      creature = floor.monster x, y
      return Palette[creature] if creature

      item = floor.items(x, y).last?
      return Palette[item] if item

      fitting = floor.fixture x, y
      return Palette[fitting] if fitting

      Palette[tile.terrain]
    end

    # What *x*, *y* looked like when it was last seen.
    private def remembered(x : Int32, y : Int32) : Look
      held = @knowledge
      memory = held.try &.[](x, y)
      return Palette::UNSEEN unless memory

      # A creature is not remembered here. Phase 19 gives `Memory` one, so
      # that a monster last seen somewhere stays drawn there until the
      # character looks again.
      item = memory.item
      fitting = memory.fixture

      look = if item
               Palette[item]
             elsif fitting
               Palette[fitting]
             else
               Palette[memory.terrain]
             end

      Palette.shaded look, Palette::REMEMBERED
    end

    # How much light is on *x*, *y*.
    private def light(x : Int32, y : Int32) : Int32
      found = @sight
      return Palette::STEPS if found.nil?

      Math.max found.light(x, y), 1
    end

    # Whether the character can see *x*, *y*.
    #
    # A pane with no field of view set sees everything. A spec that is not
    # about sight then needs to say nothing about sight.
    def seen?(x : Int32, y : Int32) : Bool
      found = @sight
      found ? found.includes?(x, y) : true
    end

    # Puts *look* on *x*, *y*. It stays until `#clear_marks`.
    def mark(x : Int32, y : Int32, look : Look) : Nil
      @marks[{x, y}] = look
    end

    # Takes everything off the terrain.
    def clear_marks : Nil
      @marks.clear
    end

    # Offers *x*, *y* as an answer to a question.
    def highlight(x : Int32, y : Int32) : Nil
      @highlights << {x, y}
    end

    # Stops offering anything.
    def clear_highlights : Nil
      @highlights.clear
    end

    # Draws *x*, *y* on *colour* while a shot is being aimed.
    def aim(x : Int32, y : Int32, colour : TermBuf::Color) : Nil
      @flight[{x, y}] = colour
    end

    # Takes the aimed line off.
    def clear_flight : Nil
      @flight.clear
    end

    # Whether *x*, *y* is offered.
    def highlighted?(x : Int32, y : Int32) : Bool
      @highlights.includes?({x, y})
    end

    # What is on *x*, *y* over the terrain. `nil` for bare ground.
    def mark?(x : Int32, y : Int32) : Look?
      @marks[{x, y}]?
    end

    # Which floor is being shown.
    def floor : Floor
      @cells.floor
    end

    # Shows *floor* instead, from its top left corner.
    def floor=(floor : Floor) : Floor
      @cells.floor = floor
      @grid.scroll_to 0, 0
      clear_marks
      clear_highlights
      clear_flight
      @sight = nil
      @knowledge = nil
      floor
    end

    # Moves the camera as little as it takes to keep *x*, *y* off the edge of
    # the window. Following the character uses this.
    def follow(x : Int32, y : Int32) : Nil
      @grid.reveal x, y, margin: @margin
    end

    # Moves the camera so that *x*, *y* and the squares around it fall outside
    # *area*. Answers whether the camera moved.
    def avoid(x : Int32, y : Int32, area : TermBuf::Rect) : Bool
      @grid.avoid x, y, area, margin: @avoid_margin
    end

    # Puts the camera back where *camera* had it.
    def camera=(camera : {Int32, Int32}) : Nil
      @grid.scroll_to camera[0], camera[1]
    end

    # Puts *x*, *y* in the middle of the window. Stops at the edges of the
    # floor.
    def center_on(x : Int32, y : Int32) : Nil
      @grid.center_on x, y
    end

    # Which square of the floor is at *screen_x*, *screen_y* of the buffer.
    # `nil` when the pointer is not over a square.
    def cell_at_screen(screen_x : Int32, screen_y : Int32) : {Int32, Int32}?
      @grid.cell_at_screen screen_x, screen_y
    end

    # Where the floor's *x*, *y* is drawn, in buffer coordinates. `nil` when
    # that square is not showing.
    def screen_of(x : Int32, y : Int32) : {Int32, Int32}?
      @grid.screen_of x, y
    end

    # Where the camera is.
    def camera : {Int32, Int32}
      {@grid.scroll_x, @grid.scroll_y}
    end

    # Which square is in the middle of the window.
    #
    # A window larger than the floor shows the floor in one corner of itself.
    # The middle of such a window is past the edge of the floor. The answer is
    # clamped onto the floor, because every caller wants a square that exists.
    def middle : {Int32, Int32}
      room = @grid.viewport_size
      here = {@grid.scroll_x + room[0] // 2, @grid.scroll_y + room[1] // 2}

      {here[0].clamp(0, Math.max(floor.columns - 1, 0)),
       here[1].clamp(0, Math.max(floor.rows - 1, 0))}
    end
  end
end
