module Roguelike::Ui
  # What the character is, stacked down the sidebar.
  #
  # Everything a person reads every turn, in one column: the level, the bars,
  # the numbers that are not on a bar, the five scores, what is readied, and
  # what is in the pack.
  #
  # An empty equipment slot is drawn dimmed rather than left out, so a person
  # learns which row the weapon is on instead of reading the labels.
  #
  # The pane is taller than a short terminal can give it. `#fit` decides what
  # to show and what to leave out, from the bottom up, so the level and the
  # hit points survive any window the game will run in at all.
  class CharacterPane
    # The heading over the equipment slots.
    WORN = "Worn/Wielded"

    # The heading over the pack.
    PACK = "Pack"

    # What marks a section that is open, and one that is shut.
    OPEN = '▼'
    SHUT = '▶'

    # What an empty slot says.
    NOTHING = "—"

    # What the first row says for a character nobody has named.
    #
    # A run holds no name until the title screen has been answered, and a
    # spec builds a character without going near the title screen.
    NOBODY = "—"

    # Where an item's name starts on a slot row.
    #
    # There is no glyph on these rows. The slot word says what sort of thing
    # is in the slot, and the two columns a glyph would take are two more of
    # the name.
    NAME = 4

    # The same on a pack row, where a letter takes the first column.
    PACK_GLYPH = 2
    PACK_NAME  = 4

    # The fewest rows the pane ever takes.
    #
    # The level, the hit points and the experience, a blank row, and the
    # armour class beside the gold and the turn. Nothing takes those away: a
    # window with no room for them has no room for the game.
    LEAST = 5

    # How many pack rows there are. A longer pack ends with a row saying how
    # much was left out.
    MOST_PACK = 10

    # The widget itself. A caller puts it in a tree.
    getter root : Widgets::Panel

    # The first row: who the character is, and what level they have reached.
    getter who : Line

    # The three bars.
    getter health : Meter
    getter magic : Meter
    getter learning : Meter

    # Armour class, gold and the turn.
    getter numbers : Line

    # The five scores, under their names.
    getter score_names : Line
    getter scores : Line

    # One row per equipment slot, in `Slot.listed` order.
    getter slots : Array(Line)

    # One row per pack entry, and one more for what did not fit.
    getter pack : Array(Line)

    # The row each section is headed with.
    getter worn_heading : Line
    getter pack_heading : Line

    # The blocks, in the order they are stacked.
    getter vitals : Widgets::Panel
    getter tally : Widgets::Panel
    getter scoring : Widgets::Panel
    getter worn : Widgets::Panel
    getter packed : Widgets::Panel

    # Whether the pack section is open.
    #
    # Shut to begin with. The pack is ten rows and the readouts under the
    # pane want them, and a person who wants the list opens it on the
    # triangle or presses `i`.
    getter? showing_pack : Bool = false

    # Whether an empty slot is drawn at all.
    #
    # `#fit` turns this off on a screen with no room for eight rows of
    # equipment. A slot with something in it is always drawn.
    getter? showing_vacant : Bool = true

    # Which slots had something in them when `#show` last ran.
    #
    # `#fit` reads this to work out how tall the equipment block would be
    # with the empty rows left out. It cannot read the rows themselves: it
    # is what decides whether they are hidden.
    @filled : Array(Bool) = Array.new(Slot.listed.size, false)

    def initialize
      @who = Line.new
      @health = Meter.new "HP", levels: Palette::HEALTH
      @magic = Meter.new "MP", levels: Palette::MAGIC
      @learning = Meter.new "XP", levels: Palette::LEARNING
      @numbers = Line.new
      @score_names = Line.new
      @scores = Line.new
      @slots = Slot.listed.map { Line.new }
      @pack = Array.new(MOST_PACK + 1) { Line.new }
      @worn_heading = CharacterPane.heading WORN
      @pack_heading = CharacterPane.heading PACK

      # Nothing has magic yet. The bar is built and hidden, so the day
      # `Player` grows a pool this line goes and the layout is already right.
      @magic.hidden = true

      @vitals = CharacterPane.block @who, @health, @magic, @learning
      @tally = CharacterPane.block @numbers
      @scoring = CharacterPane.block @score_names, @scores

      @worn_rows = CharacterPane.block @slots.map &.as(Widgets::Widget)
      @worn = CharacterPane.block @worn_heading,
        Widgets::Divider.new(Widgets::Divider::Orientation::Horizontal),
        @worn_rows

      @pack_rows = CharacterPane.block @pack.map &.as(Widgets::Widget)
      @packed = CharacterPane.block @pack_heading,
        Widgets::Divider.new(Widgets::Divider::Orientation::Horizontal),
        @pack_rows

      # A blank row between blocks. A hidden block takes no gap with it.
      @root = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.fit,
        gap: 1)
      @root.add @vitals, @tally, @scoring, @worn, @packed
      @pack_rows.hidden = true
    end

    # A column of *widgets*, sized to what they need.
    def self.block(widgets : Enumerable(Widgets::Widget)) : Widgets::Panel
      panel = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.fit)
      widgets.each { |widget| panel.add widget }
      panel
    end

    # :ditto:
    def self.block(*widgets : Widgets::Widget) : Widgets::Panel
      block widgets.to_a.map &.as(Widgets::Widget)
    end

    # A heading over a section.
    #
    # A `Line` rather than a `Widgets::Label`, because a label is as tall as
    # its text needs and the layout squeezes it to nothing before it squeezes
    # a row of fixed height. A heading that vanishes under pressure leaves a
    # rule over a list of nothing in particular.
    def self.heading(title : String) : Line
      Line.new
    end

    # How many rows the pane takes as it stands.
    def height : Int32
      rows = 0
      {@vitals, @tally, @scoring, @worn, @packed}.each do |block|
        next if block.hidden?

        rows += CharacterPane.rows(block) + (rows.zero? ? 0 : 1)
      end

      rows
    end

    # How many rows *block* takes, its hidden children left out.
    def self.rows(block : Widgets::Panel) : Int32
      block.children.sum do |child|
        next 0 if child.hidden?
        next rows child if child.is_a? Widgets::Panel

        1
      end
    end

    # Decides what to show in *room* rows.
    #
    # Things go in the order a person would give them up. An open pack shuts
    # first, because it is a list they can open again. Empty slots go next,
    # because a slot with nothing in it says nothing. The scores go next,
    # because they change a few times in a run. The pack heading and then the
    # equipment go last. The level and the bars never go.
    # Run it after `#show`, which is what records how much there is to fit.
    def fit(room : Int32) : Nil
      {@scoring, @worn, @packed}.each &.hidden=(false)
      vacant true
      @pack_rows.hidden = !@showing_pack
      return if height <= room

      @pack_rows.hidden = true
      return if height <= room

      vacant false
      return if height <= room

      @scoring.hidden = true
      return if height <= room

      @packed.hidden = true
      return if height <= room

      @worn.hidden = true
    end

    # Shows or hides the rows of the slots with nothing in them.
    private def vacant(wanted : Bool) : Nil
      @showing_vacant = wanted
      @slots.each_with_index do |row, index|
        row.hidden = !wanted && !@filled[index]
      end
    end

    # The row *slot* is written on.
    def slot_row(slot : Slot) : Line
      @slots[Slot.listed.index(slot) || 0]
    end

    # Opens the pack section, or shuts it.
    def toggle_pack : Nil
      @showing_pack = !@showing_pack
      @pack_rows.hidden = !@showing_pack
      head @pack_heading, PACK, @showing_pack
    end

    # Writes what *game* holds.
    def show(game : Game) : Nil
      player = game.player

      @who.clear
      @who.put 0, player.name.empty? ? NOBODY : player.name, Palette::STRONG
      @who.put_right "Lv #{player.level}", Palette::PLAIN

      @health.show player.hit_points, player.max_hit_points
      @magic.show 0, 0
      learned player

      @numbers.clear
      @numbers.put 0, "ac", Palette::FAINT
      @numbers.put 3, player.armour_class.to_s, Palette::STRONG
      @numbers.put 7, "au", Palette::FAINT
      @numbers.put 10, player.gold.to_s, Palette::COIN
      @numbers.put 16, "t", Palette::FAINT
      @numbers.put 18, game.turn.to_s, Palette::PLAIN

      written_scores player
      written_slots game
      written_pack game

      head @worn_heading, WORN, nil
      head @pack_heading, PACK, @showing_pack
    end

    # Writes a section heading, with the triangle when it can be shut.
    private def head(row : Line, title : String, open : Bool?) : Nil
      row.clear
      return row.put 0, title, Style::DEFAULT.bold if open.nil?

      row.put 0, (open ? OPEN : SHUT).to_s, Palette::FAINT
      row.put 2, title, Style::DEFAULT.bold
    end

    # The experience bar: how far through the level the character is.
    #
    # The bar is the part of this level that is done rather than the points
    # in hand, so a full bar always means the next level. The last level has
    # no next one and the bar sits full.
    private def learned(player : Player) : Nil
      wanted = player.to_next_level
      unless wanted
        @learning.show 1, 1, player.experience.to_s
        return
      end

      here = Advancement.threshold player.level
      span = Advancement.threshold(player.level + 1) - here

      @learning.show player.experience - here, span,
        "#{player.experience}/#{player.experience + wanted}"
    end

    # The five scores, with their names over them.
    private def written_scores(player : Player) : Nil
      @score_names.clear
      @scores.clear

      Attributes::Which.values.each_with_index do |which, index|
        @score_names.put index * 3, which.short, Palette::FAINT
        @scores.put index * 3, player.attributes[which].to_s.rjust(2), Palette::PLAIN
      end
    end

    # One row per slot: the slot word, the item's glyph, and its name.
    #
    # Every row is written whether or not it is shown. `#fit` decides what is
    # shown, and it runs after this.
    private def written_slots(game : Game) : Nil
      Slot.listed.each_with_index do |slot, index|
        row = @slots[index]
        item = game.player.in_slot slot
        @filled[index] = !item.nil?

        row.clear
        row.put 0, slot.short, Palette::FAINT

        unless item
          row.put NAME, NOTHING, Palette::VACANT
          next
        end

        row.put NAME, Naming.short(game.lore, item), Palette[item].style
      end
    end

    # The pack, one entry to a row, by the letter it is carried under.
    private def written_pack(game : Game) : Nil
      entries = game.player.inventory.entries
      @pack.each do |row|
        row.clear
        row.hidden = true
      end

      entries.first(MOST_PACK).each_with_index do |(letter, item), index|
        look = Palette[item]
        row = @pack[index]
        row.hidden = false
        row.put 0, letter.to_s, Palette::FAINT
        row.put PACK_GLYPH, look.glyph.to_s, look.style
        row.put PACK_NAME, Naming.short(game.lore, item), look.style
      end

      left = entries.size - MOST_PACK
      return unless left > 0

      @pack[MOST_PACK].hidden = false
      @pack[MOST_PACK].put 0, "#{left} more", Palette::FAINT
    end
  end
end
