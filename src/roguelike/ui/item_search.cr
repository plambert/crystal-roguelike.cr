require "../../crystal-roguelike"

module Roguelike::Ui
  # The items the character remembers on the floor, nearest first.
  #
  # Everything here reads what the character remembers. Nothing reads the
  # floor, so the list never says more than they know.
  module ItemSearch
    # One remembered item. *spot* is where it lies, *name* is what the
    # character calls it, *steps* is how far they would walk to reach it,
    # and *age* is how many turns ago they last saw it. *steps* is `nil`
    # when they know no way there.
    record Entry,
      spot : {Int32, Int32},
      item : Item,
      name : String,
      steps : Int32?,
      age : Int32

    # Every item the character remembers on the floor they are on, nearest
    # first. Items with no known way to them come last.
    #
    # One flood from the character gives every distance. It crosses known
    # ground and doors, which is what a walk to the item would cross.
    def self.entries(game : Game) : Array(Entry)
      knowledge = game.knowledge
      flood = Descent.toward knowledge, game.player.at, Route.limit(game.floor), doors: true
      found = [] of Entry

      knowledge.each_item do |column, row, memory|
        steps = flood[column, row]
        memory.items.each do |remembered|
          name = game.name remembered.item, regard: remembered.regard
          age = Math.max game.turn - remembered.turn, 0
          found << Entry.new({column, row}, remembered.item, name, steps, age)
        end
      end

      found.sort_by! do |entry|
        {entry.steps ? 0 : 1, entry.steps || 0, entry.name, entry.spot[1], entry.spot[0], entry.item.id}
      end
    end

    # Whether *name* matches *query*. Case is ignored, and an empty query
    # matches everything.
    def self.matches?(name : String, query : String) : Bool
      wanted = query.strip.downcase
      wanted.empty? || name.downcase.includes?(wanted)
    end

    # The entries whose names match *query*, in the order given.
    def self.matching(entries : Array(Entry), query : String) : Array(Entry)
      entries.select { |entry| matches? entry.name, query }
    end

    # *names* with the ones matching *query* first. Each part keeps its
    # order. An empty query changes nothing.
    def self.matches_first(names : Array(String), query : String) : Array(String)
      return names if query.strip.empty?

      hits, misses = names.partition { |name| matches? name, query }
      hits + misses
    end

    # How far away *steps* is, as a row says it.
    def self.distance(steps : Int32?) : String
      case steps
      when nil then "no path"
      when 0   then "here"
      when 1   then "1 step"
      else          "#{steps} steps"
      end
    end

    # How long ago *turns* turns is, as a row says it. A turn is
    # `Sustenance::SECONDS_PER_TURN` seconds.
    def self.ago(turns : Int32) : String
      seconds = Math.max(turns, 0).to_i64 * Sustenance::SECONDS_PER_TURN
      return "now" if seconds.zero?
      return "#{seconds}s ago" if seconds < 60

      minutes = seconds // 60
      return "#{minutes}m ago" if minutes < 60

      hours, left = minutes.divmod 60
      return "#{hours}h ago" if left.zero? || hours >= 10

      "#{hours}h#{left}m ago"
    end
  end

  # The search panel, against the left or the right edge of the screen.
  #
  # A line to type on, a count, a button for the map, and the list of
  # remembered items. Typing narrows the list. `Up` and `Down` choose an
  # item, and `Play` draws the way to it on the part of the map the panel
  # leaves clear. `Play` moves the panel to the other edge when the item
  # cannot be brought out from behind it.
  #
  # The panel holds no rule of its own. `Play` fills it and answers what it
  # reports.
  class ItemSearchPane < Widgets::Overlay
    # The key that opens the panel.
    KEY = "/"

    # The key that swaps the panel for the map, and back.
    MAP_KEY = "Tab"

    # What is drawn in the top edge of the box.
    TITLE = " find an item "

    # What sits in front of the line being typed.
    PROMPT = "Find: "

    # What the line says while nothing is typed.
    PLACEHOLDER = "type part of a name"

    # What the button for the map says.
    MAP_BUTTON = " Map (Tab) "

    # What the bottom row says.
    FOOTER = "Up Down choose · Tab map · Esc close"

    # The narrowest panel and the widest.
    WIDTHS = {48, 72}

    # The share of the screen's width the panel takes, in percent, between
    # those two.
    SHARE = 45

    # The shortest panel.
    LEAST_HEIGHT = 10

    # How many cells the panel leaves clear above and below itself and
    # beside the edge it sits against.
    MARGIN = 1

    # The width of the distance column and of the age column.
    DISTANCE_WIDTH = 9
    AGE_WIDTH      = 9

    # A line that says when its text changed.
    class Query < Widgets::Field
      # What runs after a key or a paste that changed the text.
      property on_change : Proc(Nil)? = nil

      def press(key : TermBuf::Key) : Nil
        before = text
        super
        @on_change.try &.call unless text == before
      end

      def paste(text : String) : Nil
        before = self.text
        super
        @on_change.try &.call unless self.text == before
      end
    end

    # The line being typed.
    getter query : Query

    # How many items there are and how many match.
    getter count : Widgets::Label

    # The button that swaps the panel for the map.
    getter map_button : Widgets::Label

    # The rows.
    getter list : Widgets::VirtualList(ItemSearch::Entry)

    # The bottom row.
    getter footer : Widgets::Label

    # The entries the list shows, in its order.
    getter shown : Array(ItemSearch::Entry) = [] of ItemSearch::Entry

    # What runs when the text changes.
    property on_change : Proc(String, Nil)? = nil

    # What runs when a different row is chosen.
    property on_choose : Proc(ItemSearch::Entry?, Nil)? = nil

    # What runs when the panel is to give way to the map.
    property on_map : Proc(Nil)? = nil

    # What runs when the panel is to close.
    property on_close : Proc(Nil)? = nil

    # Where the panel sits on the screen, as `#fit_into` last placed it.
    getter area : Rect = Rect.new(0, 0, 0, 0)

    # Whether the panel sits against the right edge rather than the left.
    getter? right : Bool = false

    # The screen `#fit_into` last sized the panel to.
    @screen : Rect = Rect.new(0, 0, 0, 0)

    def initialize(z : Int32 = Z::DIALOG)
      @query = Query.new(
        editor: Widgets::Editor.new,
        prompt: Widgets::Field::Prompt.new(PROMPT))
      @query.placeholder = PLACEHOLDER
      @count = Widgets::Label.new "", wrap: Layout::Wrap::None, ellipsis: "…"
      @map_button = Widgets::Label.new MAP_BUTTON, wrap: Layout::Wrap::None
      @list = Widgets::VirtualList(ItemSearch::Entry).new Widgets::Rows.of(@shown)
      @footer = Widgets::Label.new FOOTER, wrap: Layout::Wrap::None, ellipsis: "…"

      super modal: true, backdrop: false, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @width = Layout::Sizing.fixed WIDTHS[0]
      @height = Layout::Sizing.fixed LEAST_HEIGHT
      @border = Widgets::Border.rounded title: TITLE
      @floating = Layout::Floating.on nil, Layout::AttachPoint::LeftTop,
        Layout::AttachPoint::LeftTop, dx: MARGIN, dy: MARGIN, z: z

      @query.on_change = -> { @on_change.try &.call(@query.text); nil }

      @count.width = Layout::Sizing.grow
      @map_button.width = Layout::Sizing.fit
      top = Widgets::Panel.new
      top.direction = Layout::Direction::Row
      top.width = Layout::Sizing.grow
      top.height = Layout::Sizing.fixed 1
      top.add @count, @map_button

      @list.keymap = nil
      @list.height = Layout::Sizing.grow
      @list.on_draw = ->(view : View, _index : Int32, entry : ItemSearch::Entry, chosen : Bool, _lit : Bool) do
        ItemSearchPane.draw_row view, entry, chosen
        nil
      end

      self.keymap = moving
      add @query, top, @list, @footer
      restyle
    end

    # Sets the colors from the palette. A new theme calls this again.
    def restyle : Nil
      @count.style = Palette.dimmed
      @footer.style = Palette.dimmed
      @map_button.style = Palette.header
    end

    # Draws *entry* on one row of *view*: its glyph, its name, how far and
    # how long ago. A chosen row is drawn on the selection color, glyph and
    # all in plain text, because some item colors are hard to read on it.
    def self.draw_row(view : View, entry : ItemSearch::Entry, chosen : Bool) : Nil
      look = Palette[entry.item]
      ground = Palette.selected_row
      text = chosen ? Palette.plain.bg(ground) : Palette.plain
      quiet = chosen ? text : Palette.dimmed
      view.fill Rect.new(0, 0, view.width, 1), ' ', text if chosen

      view.write_char 1, 0, look.glyph, chosen ? text : look.style
      right = DISTANCE_WIDTH + 2 + AGE_WIDTH
      room = Math.max view.width - 3 - right - 1, 1
      view.write 3, 0, ItemSearchPane.fit(entry.name, room), text

      steps = ItemSearch.distance(entry.steps).rjust(DISTANCE_WIDTH)
      seen = ItemSearch.ago(entry.age).rjust(AGE_WIDTH)
      view.write Math.max(view.width - right, 3), 0, "#{steps}  #{seen}", quiet
    end

    # *text* cut to *room* cells, with an ellipsis where it was cut.
    def self.fit(text : String, room : Int32) : String
      return text if TermBuf::Unicode.string_width(text) <= room

      kept = String.build do |io|
        used = 0
        text.each_char do |char|
          width = TermBuf::Unicode.char_width char
          break if used + width > room - 1

          io << char
          used += width
        end
      end
      "#{kept}…"
    end

    # Whether the panel is up.
    def showing? : Bool
      open?
    end

    # Sizes the panel to *screen*.
    #
    # It sits against one edge and takes a share of the width, so the rest
    # of the map stays in view.
    def fit_into(screen : Rect) : Nil
      @screen = screen
      width = (screen.width * SHARE // 100).clamp(WIDTHS[0], WIDTHS[1])
      width = Math.min width, Math.max(screen.width - 2 * MARGIN, 1)
      height = Math.max screen.height - 2 * MARGIN, LEAST_HEIGHT

      self.width = Layout::Sizing.fixed width
      self.height = Layout::Sizing.fixed height
      left = @right ? screen.right - MARGIN - width : screen.x + MARGIN
      @area = Rect.new(left, screen.y + MARGIN, width, height)
      corner = @right ? Layout::AttachPoint::RightTop : Layout::AttachPoint::LeftTop
      self.floating = Layout::Floating.on nil, corner, corner,
        dx: @right ? -MARGIN : MARGIN, dy: MARGIN, z: z
    end

    # Moves the panel to the other edge of the screen.
    def flip : Nil
      @right = !@right
      fit_into @screen
    end

    # Puts the panel up on *app* with *query* typed.
    def show(app : Widgets::App, query : String) : Nil
      fit_into app.tree.screen
      @query.text = query
      open app
    end

    # Takes the panel down.
    def hide : Nil
      close
    end

    # Shows *entries* of *total*, keeping the row on the item with the id
    # *keep* when it is still there.
    def fill(entries : Array(ItemSearch::Entry), total : Int32, keep : Int32? = nil) : Nil
      @shown.replace entries
      @list.rows = Widgets::Rows.of(@shown)
      @count.text = ItemSearchPane.counted entries.size, total, @query.text
      index = keep.try { |id| @shown.index(&.item.id.== id) } || 0
      @list.select index
    end

    # What the count says.
    def self.counted(found : Int32, total : Int32, query : String) : String
      return "You remember no items on this floor." if total.zero?
      return "#{total} #{total == 1 ? "item" : "items"}, nearest first" if query.strip.empty?
      return "Nothing you remember matches." if found.zero?

      "#{found} of #{total} match"
    end

    # The chosen entry, or `nil` when the list is empty.
    def chosen : ItemSearch::Entry?
      @list.current
    end

    # Moves the selection *rows* rows down, up when negative.
    def move(rows : Int32) : Nil
      before = @list.selected
      @list.select before + rows
      @on_choose.try &.call(chosen) unless @list.selected == before
    end

    # The keyboard lands on the line being typed.
    def focusable? : Bool
      false
    end

    # What the line says, and the mouse.
    #
    # `Enter` swaps the panel for the map. `Escape` and `Ctrl+C` reach the
    # line only when nothing above it claims them, and close the panel.
    # A click on a row chooses it. A click on the button swaps the panel
    # for the map.
    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      case event
      when Widgets::Field::Accepted
        context.consume
        @on_map.try &.call
      when Widgets::Field::Cancelled, Widgets::Field::EndOfInput
        context.consume
        @on_close.try &.call
      when TermBuf::Events::Mouse
        clicked event, context
      end
    end

    private def clicked(event : TermBuf::Events::Mouse, context : Widgets::Context) : Nil
      return unless event.button.left? && event.action.press?

      if @map_button.rect.contains? event.x, event.y
        context.consume
        return @on_map.try &.call
      end

      box = @list.rect
      return unless box.contains? event.x, event.y

      context.consume
      index = @list.visible_range.begin + (event.y - box.y)
      return unless index < @shown.size

      move index - @list.selected
    end

    # The keys the panel answers over the line.
    private def moving : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Up"), "the item before",
          ->(_context : Widgets::Context) { move -1; nil }
        map.bind TermBuf::Key.parse("Down"), "the item after",
          ->(_context : Widgets::Context) { move 1; nil }
        map.bind TermBuf::Key.parse("PageUp"), "a page of items back",
          ->(_context : Widgets::Context) { move -@list.page; nil }
        map.bind TermBuf::Key.parse("PageDown"), "a page of items on",
          ->(_context : Widgets::Context) { move @list.page; nil }
        map.bind TermBuf::Key.parse(MAP_KEY), "show the matches on the map",
          ->(_context : Widgets::Context) { @on_map.try &.call; nil }
        map.bind TermBuf::Key.parse("Escape"), "close the search",
          ->(_context : Widgets::Context) { @on_close.try &.call; nil }
      end
    end
  end

  # The bar along the top of the map while the search shows its matches
  # there.
  #
  # It holds no keys. `Play` answers `Tab` and `Escape` while the matches
  # are on the map. A click on the bar goes back to the panel.
  class ItemSearchBar < Widgets::Overlay
    # The label.
    getter label : Widgets::Label

    # What runs when the bar is clicked.
    property on_click : Proc(Nil)? = nil

    def initialize(z : Int32 = Z::POPOVER)
      @label = Widgets::Label.new "", wrap: Layout::Wrap::None, ellipsis: "…"
      super modal: false, backdrop: false, light_dismiss: false, z: z
      @width = Layout::Sizing.fit
      @height = Layout::Sizing.fixed 1
      add @label
    end

    # What the bar says for *query* with *found* matches.
    def self.said(query : String, found : Int32) : String
      what = query.strip.empty? ? "all items" : "\"#{query.strip}\""
      lit = found == 1 ? "1 item lit" : "#{found} items lit"
      " Finding #{what}: #{lit} · Tab or click here for the list · Esc "
    end

    # Puts the bar up on *app*, along the top of *map*.
    def show(app : Widgets::App, map : Widgets::Widget, query : String, found : Int32) : Nil
      @label.text = ItemSearchBar.said(query, found)
      @label.style = Palette.header
      self.floating = Layout::Floating.on map,
        Layout::AttachPoint::CenterTop, Layout::AttachPoint::CenterTop,
        z: z, overflow: Layout::Overflow::Clamp
      open app
    end

    # Takes the bar down.
    def hide : Nil
      close
    end

    # Whether the bar is up.
    def showing? : Bool
      open?
    end

    # The bar never takes the keyboard.
    def focusable? : Bool
      false
    end

    # A click on the bar goes back to the panel.
    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      return unless event.is_a? TermBuf::Events::Mouse
      return unless event.button.left? && event.action.press?
      return unless frame.contains? event.x, event.y

      context.consume
      @on_click.try &.call
    end
  end
end
