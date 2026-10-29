require "../../crystal-roguelike"

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

    # How much of the window the followed square moves freely inside, as a
    # percentage of the window on each axis.
    #
    # The character walks about a box this big in the middle of the window and
    # the camera holds still. The camera moves once they reach the edge of it,
    # and stops once it has run out of floor to scroll onto, so a character in
    # a corner of the floor stands in a corner of the window.
    #
    # A count of cells cannot do this job. Six cells is most of the height of
    # a short terminal and a sliver of a tall one, so the same number gives
    # two windows two different games.
    property box : Int32 = BOX

    # What `#box` starts at. Half the window on each axis.
    BOX = 50

    # Squares kept clear around the character when a modal box covers part of
    # the window.
    property avoid_margin : Int32 = 3

    # What the character can see from where they stand. `nil` draws every
    # square, which is what a pane with no game behind it does.
    #
    # A square outside this draws as `Palette.unseen`. Nothing on it draws
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
    # The cursor marks its square rather than replacing what is on it, so
    # the glyph under it stays readable.
    property cursor : {Int32, Int32}? = nil

    # The square lit for the creature pointed at in the Seen list. `nil`
    # lights nothing.
    #
    # The glyph stays and the whole cell takes `Palette.spotlit`, so the
    # square stands out from routes, aimed lines and the cursor.
    property spotlight : {Int32, Int32}? = nil

    # What is standing on a square. It draws over the terrain. It is not
    # written into the floor.
    #
    # The character goes here now. Monsters and dropped items go here later.
    # Whatever owns the game state fills this table. A pane draws a floor. It
    # holds nothing about the creatures on it.
    getter marks : Hash({Int32, Int32}, Look) = {} of {Int32, Int32} => Look

    # What the squares in sight looked like at one moment, drawn in place of
    # what is on them now. `nil` draws the floor as it is.
    #
    # A missile is drawn crossing the floor after the run has moved on. The
    # arrow is already lying where it stopped and whatever it killed is
    # already gone, and this is the picture it is drawn over instead. A mark
    # still draws over it, and a square it has nothing for draws live.
    getter frozen : Hash({Int32, Int32}, Look)? = nil

    # Squares offered as an answer to a question.
    #
    # Each keeps its own glyph and its own color. Only the background
    # changes. A person choosing between four doors has to see which door is
    # which.
    getter highlights : Set({Int32, Int32}) = Set({Int32, Int32}).new

    # Squares a shot would cross, and the color each is drawn on.
    #
    # The line is one color and the square the shot stops on is another. A
    # person aiming has to see where the line runs and where it ends.
    getter flight : Hash({Int32, Int32}, TermBuf::Color) = {} of {Int32, Int32} => TermBuf::Color

    # The squares the character's last noise reached, each with how far the
    # sound had traveled there and the step of the tint it draws at.
    #
    # Only a square the character can see or remembers is tinted. A tint on
    # a blank square would draw the shape of ground nobody has seen.
    getter echo : Hash({Int32, Int32}, {Int32, Int32}) = {} of {Int32, Int32} => {Int32, Int32}

    # How far out the tint is drawn while it spreads. `nil` draws all of it.
    #
    # The squares at the front draw on `Palette.noise_wave`, so the tint
    # moves out as a ring along the distance map.
    property echo_front : Int32? = nil

    # Where sounds heard from out of sight are marked. `Game` puts each on a
    # square in sight or on the square beside the character, so a mark
    # draws no ground the character does not know.
    getter heard : Set({Int32, Int32}) = Set({Int32, Int32}).new

    # Whether those marks are drawn now. A blink turns this off and on.
    getter? heard_lit : Bool = true

    # How many drawings of the window an idle pane keeps.
    #
    # The flames go round these in order. Eight shifts of `Flicker::HOLD`
    # ticks each last a little over two seconds, which is long enough that
    # the loop does not show.
    FRAMES = 8

    # Whether nobody is looking at the window.
    #
    # An idle pane works out each of `FRAMES` shifts of the flames once. After
    # that it draws the ones it kept, in turn, and works out no square at all.
    # This holds only while the flames are burning.
    getter? idle : Bool = false

    # How many squares the pane has worked out how to draw. A kept drawing
    # adds nothing to it.
    getter worked : Int64 = 0

    # The drawings an idle pane keeps, by which of `FRAMES` each one is.
    @frames = {} of Int32 => Frame

    # The drawing this frame records into. `nil` when it records nothing.
    @recording : Frame? = nil

    def initialize(floor : Floor)
      @cells = FloorCells.new floor
      @grid = Widgets::CellGrid.new @cells
      @grid.background = Palette.ground_style
      @grid.on_draw = ->(view : TermBuf::View, x : Int32, y : Int32, tile : Tile) do
        look = looked_at x, y, tile
        look = Palette.heard_mark if @heard_lit && @heard.includes?({x, y})

        style = look.style
        style = echoed x, y, look, style
        style = style.bg Palette.offered if @highlights.includes?({x, y})

        aimed = @flight[{x, y}]?
        style = style.bg aimed if aimed
        style = Palette.spotlit if @spotlight == {x, y}

        here = @cursor
        style = style.reverse if here && here[0] == x && here[1] == y

        view.write_char 0, 0, look.glyph, style
        @worked += 1
        @recording.try &.put(x, y, look.glyph, style)
        nil
      end
      @grid.on_frame = ->(view : TermBuf::View) { replayed view }
    end

    # *style* tinted for the character's noise, when it reached *x*, *y*
    # and the spreading tint has got there.
    private def echoed(x : Int32, y : Int32, look : Look, style : Style) : Style
      found = @echo[{x, y}]?
      return style unless found
      return style if look == Palette.unseen

      front = @echo_front
      return style if front && found[0] > front
      return Palette.heard style, Palette::NOISE_WAVE if front && found[0] == front

      Palette.heard style, found[1]
    end

    # Marks *spots* as where sounds out of sight were heard.
    def overhear(spots : Enumerable({Int32, Int32})) : Nil
      @heard.clear
      spots.each { |spot| @heard << spot }
      @heard_lit = true
      forget_frames
    end

    # Shows the marks or hides them, for a blink.
    def heard_lit=(lit : Bool) : Bool
      forget_frames
      @heard_lit = lit
    end

    # Tints the squares *echoes* reached. Where two reached the same square,
    # it keeps the nearer distance and the brighter step.
    def hear(echoes : Enumerable(Noise::Echo)) : Nil
      @echo.clear
      echoes.each do |echo|
        echo.reach.each do |spot, away|
          step = Palette.noise_step away, echo.loudness
          held = @echo[spot]?
          @echo[spot] = held ? {Math.min(held[0], away), Math.max(held[1], step)} : {away, step}
        end
      end
      forget_frames
    end

    # Takes the tint off.
    def clear_echo : Nil
      return if @echo.empty?

      @echo.clear
      @echo_front = nil
      forget_frames
    end

    # How far the furthest tinted square is from where the sound began.
    def echo_reach : Int32
      @echo.max_of?(&.[1][0]) || 0
    end

    # Takes the ground from the palette as it now stands, and drops every
    # drawing kept in the colors before.
    def retheme : Nil
      @grid.background = Palette.ground_style
      forget_frames
    end

    # Sets whether nobody is looking at the window. Drops every drawing the
    # pane keeps.
    def idle=(idle : Bool) : Bool
      forget_frames
      @idle = idle
    end

    # How many drawings the pane keeps.
    def kept : Int32
      @frames.size
    end

    # Drops every drawing an idle pane keeps. The next frame works out every
    # square again.
    #
    # Anything at all that happens while the pane is idle calls this, apart
    # from the flames moving on. A kept drawing is right only while nothing
    # else has changed.
    def forget_frames : Nil
      @frames.clear
      @recording = nil
    end

    # Draws a kept drawing on *view*, and answers true. Answers false when
    # the squares have to be worked out instead.
    #
    # An idle pane with no drawing for this shift of the flames records one
    # as the squares are worked out.
    private def replayed(view : TermBuf::View) : Bool
      @recording = nil
      slot = frame_slot
      return false unless slot

      shape = Frame::Shape.new camera, view.width, view.height
      held = @frames[slot]?

      if held && held.shape == shape
        held.draw view
        return true
      end

      made = Frame.new shape
      @frames[slot] = made
      @recording = made
      false
    end

    # Which of `FRAMES` this frame is. `nil` when the pane keeps none.
    private def frame_slot : Int32?
      return unless @idle

      found = @flicker
      return unless found && found.burning?

      found.phase % FRAMES
    end

    # One drawing of the window, kept so that an idle pane can draw it again.
    private class Frame
      # Where the camera stood and how big the window was.
      record Shape, camera : {Int32, Int32}, width : Int32, height : Int32

      # One write. *single* is a glyph that goes out alone.
      private record Run, column : Int32, row : Int32, text : String,
        style : TermBuf::Style, single : Bool

      getter shape : Shape

      @cells : Array({Char, TermBuf::Style}?)
      @runs : Array(Run)? = nil

      def initialize(@shape : Shape)
        @cells = Array({Char, TermBuf::Style}?).new @shape.width * @shape.height, nil
      end

      # Records that the field's *x*, *y* drew *glyph* in *style*.
      def put(x : Int32, y : Int32, glyph : Char, style : TermBuf::Style) : Nil
        column = x - @shape.camera[0]
        row = y - @shape.camera[1]
        return unless 0 <= column < @shape.width && 0 <= row < @shape.height

        @cells[row * @shape.width + column] = {glyph, style}
        @runs = nil
      end

      # Draws what was recorded on *view*.
      #
      # ASCII glyphs side by side in one style go out as one write. Any other
      # glyph goes out alone, through a view one cell wide, the way the grid
      # draws it.
      def draw(view : TermBuf::View) : Nil
        runs.each do |run|
          if run.single
            view.view(TermBuf::Rect.new(run.column, run.row, 1, 1))
              .write_char 0, 0, run.text[0], run.style
          else
            view.write run.column, run.row, run.text, run.style
          end
        end
      end

      private def runs : Array(Run)
        @runs ||= gathered
      end

      private def gathered : Array(Run)
        found = [] of Run

        @shape.height.times do |row|
          column = 0
          while column < @shape.width
            column = gather found, row, column
          end
        end

        found
      end

      # Adds the run that starts at *column* of *row* to *found*. Answers the
      # column after it.
      private def gather(found : Array(Run), row : Int32, column : Int32) : Int32
        base = row * @shape.width
        cell = @cells[base + column]
        return column + 1 unless cell

        glyph, style = cell
        unless glyph.ascii?
          found << Run.new(column, row, glyph.to_s, style, true)
          return column + 1
        end

        stop = column + 1
        text = String.build do |io|
          io << glyph

          while stop < @shape.width
            after = @cells[base + stop]
            break unless after && after[0].ascii? && after[1] == style

            io << after[0]
            stop += 1
          end
        end

        found << Run.new(column, row, text, style, false)
        stop
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
      # however many flames gutter at once.
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
    # glyph for the size and one color for every species, because a letter
    # and a color each name a species and a shape against light names none.
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

      Palette.shaded Palette.shape(creature.kind.size), shape_step(behind)
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

      held = @frozen.try &.[]?({x, y})
      return held if held

      standing x, y, tile
    end

    # What is on *x*, *y* now, with nothing drawn over it.
    private def standing(x : Int32, y : Int32, tile : Tile) : Look
      creature = floor.monster x, y
      return Palette[creature] if creature

      item = floor.items(x, y).last?
      return Palette[item] if item

      fitting = floor.fixture x, y
      return Palette[fitting] if fitting
      return Palette.spiked if tile.terrain.closed_door? && floor.spiked?(x, y)

      Palette[tile.terrain]
    end

    # What *x*, *y* looked like when it was last seen.
    private def remembered(x : Int32, y : Int32) : Look
      held = @knowledge
      memory = held.try &.[](x, y)
      return Palette.unseen unless memory

      # A creature is not remembered here. Phase 19 gives `Memory` one, so
      # that a monster last seen somewhere stays drawn there until the
      # character looks again.
      item = memory.item
      fitting = memory.fixture

      look = if item
               Palette[item]
             elsif fitting
               Palette[fitting]
             elsif memory.spiked? && memory.terrain.closed_door?
               Palette.spiked
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

    # How every square of *seen* looks now, with nothing drawn over it.
    #
    # `#freeze` takes one of these to draw later, once the floor has moved
    # on.
    def snapshot(seen : Vision) : Hash({Int32, Int32}, Look)
      found = {} of {Int32, Int32} => Look
      seen.each do |spot|
        found[spot] = standing spot[0], spot[1], floor.tile(spot[0], spot[1])
      end
      found
    end

    # Draws *looks* in place of what is on those squares now, until `#thaw`.
    def freeze(looks : Hash({Int32, Int32}, Look)) : Nil
      @frozen = looks
    end

    # Draws the floor as it is again.
    def thaw : Nil
      @frozen = nil
    end

    # Offers *x*, *y* as an answer to a question.
    def highlight(x : Int32, y : Int32) : Nil
      @highlights << {x, y}
    end

    # Stops offering anything.
    def clear_highlights : Nil
      @highlights.clear
    end

    # Draws *x*, *y* on *color* while a shot is being aimed.
    def aim(x : Int32, y : Int32, color : TermBuf::Color) : Nil
      @flight[{x, y}] = color
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
      @drifting = nil
      @pan = nil
      @grid.scroll_to 0, 0
      clear_marks
      clear_highlights
      clear_flight
      thaw
      @sight = nil
      @knowledge = nil
      floor
    end

    # Moves the camera as little as it takes to keep *x*, *y* inside the box
    # in the middle of the window. Following the character uses this.
    #
    # A drift in progress is dropped. The character moving is what the window
    # is for, and a camera still sliding toward a staircase would drag it off
    # them.
    def follow(x : Int32, y : Int32) : Nil
      @drifting = nil
      @pan = nil
      room = @grid.viewport_size

      @grid.reveal x, y, margin: margin(room[0]), margin_y: margin(room[1])
    end

    # Where the camera is heading. `nil` when it is where it belongs.
    getter drifting : {Int32, Int32}? = nil

    # Whether the camera is still on its way somewhere.
    def drifting? : Bool
      !@drifting.nil?
    end

    # Starts the camera moving toward the corner that brings *x*, *y* into
    # view. Answers whether it has anywhere to go.
    #
    # The camera slides a cell at a time rather than jumping. A map that jumps
    # leaves the person hunting for where they were, and the point of pointing
    # at a staircase is that they can see how to walk to it.
    def drift_to(x : Int32, y : Int32) : Bool
      wanted = camera_for x, y
      return false if wanted == camera

      @drifting = wanted
      true
    end

    # Moves the camera one cell along. Answers whether it has further to go.
    def drift : Bool
      wanted = @drifting
      return false unless wanted

      here = camera
      self.camera = {here[0] + (wanted[0] <=> here[0]),
                     here[1] + (wanted[1] <=> here[1])}

      # `#camera=` clears the drift, because putting the camera somewhere is
      # what stops one. This move is the drift, so it is put back.
      @drifting = camera == wanted ? nil : wanted
      drifting?
    end

    # A camera on its way from one corner to another over a fixed number of
    # frames.
    private record Pan,
      from : {Int32, Int32},
      to : {Int32, Int32},
      frame : Int32

    # How many frames a pan takes.
    PAN_FRAMES = 8

    # The pan under way. `nil` when the camera is not panning.
    @pan : Pan? = nil

    # Whether the camera is panning.
    def panning? : Bool
      !@pan.nil?
    end

    # Where a pan ends. `nil` when the camera is not panning.
    def pan_target : {Int32, Int32}?
      @pan.try &.to
    end

    # Starts the camera toward the corner that puts *x*, *y* in the middle of
    # the window. Answers whether it has anywhere to go.
    #
    # The corner is the one `#center_on` picks, so the edges of the floor stop
    # it the same way.
    def pan_to(x : Int32, y : Int32) : Bool
      wanted = center_for x, y
      @drifting = nil
      @pan = nil
      return false if wanted == camera

      @pan = Pan.new camera, wanted, 0
      true
    end

    # Moves the camera one frame along the pan. Answers whether it has
    # further to go.
    def pan : Bool
      going = @pan
      return false unless going

      frame = going.frame + 1
      spot = MapPane.eased going.from, going.to, frame, PAN_FRAMES
      @grid.scroll_to spot[0], spot[1]
      @pan = frame < PAN_FRAMES ? going.copy_with(frame: frame) : nil
      panning?
    end

    # Puts the camera where the pan ends, at once.
    def finish_pan : Nil
      going = @pan
      return unless going

      @pan = nil
      @grid.scroll_to going.to[0], going.to[1]
    end

    # Where a camera going from *from* to *to* stands after *frame* of
    # *frames*. `Widgets::EasedScroll.at` has the curve.
    def self.eased(from : {Int32, Int32}, to : {Int32, Int32},
                   frame : Int32, frames : Int32) : {Int32, Int32}
      Widgets::EasedScroll.at from, to, frame, frames
    end

    # Where the camera would be if it centred on *x*, *y* now.
    #
    # It is worked out by centring and putting the camera back, for the same
    # reason `#camera_for` follows and puts it back. `Play#recenter` scrolls
    # to it.
    def center_for(x : Int32, y : Int32) : {Int32, Int32}
      held = camera
      @grid.center_on x, y
      found = camera
      @grid.scroll_to held[0], held[1]

      found
    end

    # Where the camera would be if it followed *x*, *y* now.
    #
    # It is worked out by following and putting the camera back. The grid
    # owns the clamping against the edges of the floor, and working it out a
    # second time here would be a second copy of that rule.
    private def camera_for(x : Int32, y : Int32) : {Int32, Int32}
      held = camera
      follow x, y
      found = camera
      self.camera = held

      found
    end

    # How many cells the camera keeps between the followed square and the edge
    # of a window *room* cells across.
    #
    # Half of whatever the box leaves over, because the box sits in the middle
    # and the leftover is split between the two sides.
    def margin(room : Int32) : Int32
      Math.max (room - room * @box // 100) // 2, 0
    end

    # Moves the camera so that *x*, *y* and the squares around it fall outside
    # *area*. Answers whether the camera moved.
    def avoid(x : Int32, y : Int32, area : TermBuf::Rect) : Bool
      @grid.avoid x, y, area, margin: @avoid_margin
    end

    # Puts the camera back where *camera* had it. Stops a drift.
    def camera=(camera : {Int32, Int32}) : Nil
      @drifting = nil
      @pan = nil
      @grid.scroll_to camera[0], camera[1]
    end

    # Puts *x*, *y* in the middle of the window. Stops at the edges of the
    # floor, and stops a drift.
    def center_on(x : Int32, y : Int32) : Nil
      @drifting = nil
      @pan = nil
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
    # The middle of such a window is past the edge of the floor, so the square
    # is clamped onto the floor. Every caller wants a square that exists.
    def middle : {Int32, Int32}
      room = @grid.viewport_size
      here = {@grid.scroll_x + room[0] // 2, @grid.scroll_y + room[1] // 2}

      {here[0].clamp(0, Math.max(floor.columns - 1, 0)),
       here[1].clamp(0, Math.max(floor.rows - 1, 0))}
    end
  end
end
