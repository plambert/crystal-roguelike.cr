require "../../crystal-roguelike"

module Roguelike::Ui
  # What the character is, down the info panel.
  #
  # The vitals are the name and level, the bars, and the bar for whatever
  # the character is fighting. They are pinned at the top of the panel and
  # never scroll. Under them, three sections scroll with the rest of the
  # panel: the scores, the equipment, and the pack.
  #
  # An empty equipment slot is drawn dimmed rather than left out, so a person
  # learns which row the weapon is on instead of reading the labels.
  class CharacterPane
    # The scores section's title.
    SCORES = "Scores"

    # The equipment section's title.
    WORN = "Equipment"

    # What the heading over the achievements says.
    ACHIEVEMENTS = "Achievements"

    # The pack section's title.
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

    # Where the blessing mark and the item's name go on a slot row.
    #
    # The mark sits against the slot word, the way a menu puts it against
    # the key. There is no glyph on these rows. The slot word says what sort
    # of thing is in the slot, and the two columns a glyph would take are two
    # more of the name.
    MARK = 3
    NAME = 5

    # The same on a pack row, where a letter takes the first column.
    #
    # The names on both sorts of row start in the same column.
    PACK_MARK  = 1
    PACK_GLYPH = 3
    PACK_NAME  = 5

    # Whether the pack omits its traditional item-letter gutter.
    property? letterless : Bool = false

    # What the bar for the creature being fought is labeled.
    #
    # Two columns, the way `HP`, `MP` and `XP` are. The creature's name will
    # not fit in two columns, so it goes inside the bar with the count and
    # the label says who the bar is about instead.
    THREAT_LABEL = "vs"

    # The effects that get a bar with the turns they have left, in
    # `Lasting::ORDER`. Every other effect is a pill.
    BARS = [Event::Status::Hurried, Event::Status::Dragging, Event::Status::Blind]

    # What each effect with a bar is called inside it.
    #
    # The bar has no label outside it, so it lines up with the bars above
    # and the name goes in front of the count.
    LASTING_NAMES = {
      Event::Status::Hurried  => "haste",
      Event::Status::Dragging => "slow",
      Event::Status::Blind    => "blind",
    }

    # What each pill says. A pill has no count and no bar. A buff from food
    # lasts a few hundred turns, and a stage of hunger or thirst lasts until
    # the character eats or drinks.
    PILL_NAMES = {
      Event::Status::Hungry        => "hungry",
      Event::Status::Famished      => "famished",
      Event::Status::Starving      => "starving",
      Event::Status::Thirsty       => "thirsty",
      Event::Status::Parched       => "parched",
      Event::Status::Dehydrated    => "dehydrated",
      Event::Status::DyingOfThirst => "dying of thirst",
      Event::Status::WellFed       => "well fed",
      Event::Status::Refreshed     => "refreshed",
      Event::Status::SteadyAim     => "steady aim",
      Event::Status::SteadyHand    => "steady hand",
      Event::Status::Sick          => "sick",
      Event::Status::Mending       => "mending",
      Event::Status::Mighty        => "mighty",
      Event::Status::NightEyes     => "night eyes",
      Event::Status::Quickened     => "quickened",
    }

    # What the noise bar is labeled. A note, where the other bars have two
    # letters. The word goes inside the bar with the count.
    NOISE_LABEL = "♪"

    # Where the gold starts on the number rows. The armor class has the
    # columns before it.
    GOLD = 5

    # How many pack rows there are. One for every letter the pack has.
    MOST_PACK = Inventory::LETTERS.size

    # The first row: who the character is, and what level they have reached.
    getter who : Line

    # The three bars.
    getter health : Meter
    getter magic : Meter
    getter learning : Meter

    # How much water is in the skin, as text.
    #
    # A line rather than a bar. Text on the empty part of a bar does not
    # read at 4.5 to 1 in every theme.
    getter water : Line

    # The bar for the creature the character is fighting.
    getter threat : Meter

    # One bar per effect in `BARS`. A bar is hidden while its effect is not
    # running.
    getter effects : Array(Meter)

    # One pill per running effect that has no bar, in `Lasting::ORDER`, side
    # by side under the bars.
    getter pills : Widgets::Pills

    # How far the character's recent noise carries.
    getter noise : Meter

    # The row of the noise bar. Hidden while the character is quiet.
    getter noisy : Widgets::Panel

    # Armor class, gold and the turn, under their names.
    #
    # The turn sits against the right edge, so it is whole however many
    # digits it has grown to.
    getter number_names : Line
    getter numbers : Line

    # The five scores, under their names.
    getter score_names : Line
    getter scores : Line

    # How fast the character walks, and their melee damage rate.
    getter pacing : Line

    # The heading over the achievements. Hidden while there are none.
    getter achieved : Line

    # One row per achievement, oldest first: its name, and the turn it was
    # earned on. Rows are added as achievements are.
    getter achievements : Array(Line) = [] of Line

    # One row per equipment slot, in `Slot.listed` order.
    getter slots : Array(Line)

    # One row per pack entry. A row with no entry is hidden.
    getter pack : Array(Line)

    # What is pinned at the top of the panel.
    getter vitals : Widgets::Panel

    # The row of the bar for the creature being fought. Hidden while there
    # is no fight.
    getter fight : Widgets::Panel

    # The bars and the pills of the temporary effects. Hidden while there
    # are none.
    getter lasting : Widgets::Panel

    # The most turns each running effect has had left since it began.
    #
    # The game keeps only the turns left, so the pane keeps the full mark
    # the bar shrinks from. A longer reading, as when a second potion adds
    # to a haste, sets a new mark.
    @longest = {} of Event::Status => Int32

    # The three sections, in the order they are stacked.
    getter scoring : Widgets::Section
    getter worn : Widgets::Section
    getter packed : Widgets::Section

    def initialize
      @who = Line.new
      @health = Meter.new "HP", levels: Palette.health
      @magic = Meter.new "MP", levels: Palette.magic
      @learning = Meter.new "XP", levels: Palette.learning
      @water = Line.new
      @threat = Meter.new THREAT_LABEL, levels: Palette.threat
      @noise = Meter.new NOISE_LABEL, levels: Palette.noise
      @number_names = Line.new
      @numbers = Line.new
      @score_names = Line.new
      @scores = Line.new
      @pacing = Line.new
      @achieved = Line.new
      @achieved.hidden = true
      @slots = Slot.listed.map { Line.new }
      @pack = Array.new(MOST_PACK) { Line.new }

      # Nothing has magic yet. The bar is built and hidden, so the day
      # `Player` grows a pool this line goes and the layout is already right.
      @magic.hidden = true

      @fight = CharacterPane.block @threat
      @fight.hidden = true

      @effects = BARS.map { |status| Meter.new "", levels: Palette.lasting(status) }
      @effects.each(&.hidden = true)
      @pills = Widgets::Pills.new
      @pills.hidden = true
      @lasting = CharacterPane.block @effects.map(&.as(Widgets::Widget)) << @pills
      @lasting.hidden = true

      @noisy = CharacterPane.block @noise
      @noisy.hidden = true

      # The panel gives the vitals the same side columns as a section body.
      @vitals = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.fit,
        padding: Layout::Padding.symmetric(horizontal: 1))
      @vitals.add @who, @health, @magic, @learning, @water, @lasting, @noisy, @fight

      @scoring = InfoPanel.section SCORES
      @scoring.body.add @number_names, @numbers, @score_names, @scores, @pacing, @achieved

      @worn = InfoPanel.section WORN
      @slots.each { |row| @worn.body.add row }

      @packed = InfoPanel.section PACK
      @pack.each { |row| @packed.body.add row }
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

    # Gives each bar its colors from the palette as it now stands.
    def retheme : Nil
      @health.retheme Palette.health
      @magic.retheme Palette.magic
      @learning.retheme Palette.learning
      @threat.retheme Palette.threat
      BARS.each_with_index do |status, index|
        @effects[index].retheme Palette.lasting(status)
      end

      @noise.retheme Palette.noise
    end

    # The three sections, top first.
    def sections : Array(Widgets::Section)
      [@scoring, @worn, @packed]
    end

    # The equipment section's header row.
    def worn_heading : Widgets::Section::Header
      @worn.header
    end

    # The pack section's header row.
    def pack_heading : Widgets::Section::Header
      @packed.header
    end

    # Whether the pack section is open.
    def showing_pack? : Bool
      @packed.expanded?
    end

    # The row *slot* is written on.
    def slot_row(slot : Slot) : Line
      @slots[Slot.listed.index(slot) || 0]
    end

    # Opens the pack section, or shuts it.
    def toggle_pack : Nil
      @packed.toggle
    end

    # Writes what *game* holds.
    def show(game : Game) : Nil
      player = game.player

      @who.clear
      @who.put 0, player.name.empty? ? NOBODY : player.name, Palette.strong
      @who.put_right "D#{game.depth} Lv #{player.level}", Palette.plain

      @health.show player.hit_points, player.max_hit_points
      @magic.show 0, 0
      learned player
      watered player
      lasted player
      fought game
      heard game

      @number_names.clear
      @number_names.put 0, "AC", Palette.faint
      @number_names.put GOLD, "Gold", Palette.faint
      @number_names.put_right "Turn", Palette.faint

      @numbers.clear
      @numbers.put 0, player.armor_class.to_s, Palette.strong
      @numbers.put GOLD, player.gold.to_s, Palette.coin
      @numbers.put_right game.turn.to_s, Palette.plain

      written_scores player
      written_pacing game
      written_achievements player
      written_slots game
      written_pack game

      @scoring.summary = "AC #{player.armor_class}"
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

    # The water line: how many units are in the skin, out of how many it
    # holds.
    private def watered(player : Player) : Nil
      @water.clear
      @water.put 0, "water #{player.sustenance.water}/#{Sustenance::WATER_MAX}", Palette.plain
    end

    # The temporary effects on the character: a bar for each one in
    # `BARS`, and a pill for each of the rest.
    #
    # A bar is the turns left over the most it has had, so it is full when
    # the effect begins and empties as it wears off. A bar or a pill goes
    # away when its effect ends.
    private def lasted(player : Player) : Nil
      running = player.lasting
      @longest.select! { |status, _| running.any?(&.status.==(status)) }
      @lasting.hidden = running.empty?

      BARS.each_with_index do |status, index|
        bar = @effects[index]
        found = running.find(&.status.==(status))
        bar.hidden = found.nil?
        next unless found

        left = found.left || 0
        most = Math.max left, @longest[status]? || 0
        @longest[status] = most
        bar.show left, most, "#{LASTING_NAMES[status]} #{left}"
      end

      shown = running.compact_map do |held|
        name = PILL_NAMES[held.status]?
        Widgets::Pills::Pill.new name, Palette.pill(held.status) if name
      end
      @pills.pills = shown
      @pills.hidden = shown.empty?
    end

    # The bar for the creature the character is fighting.
    #
    # `Game` says which creature that is, how hurt it is and how well the
    # character has made it out. The row is hidden while there is no fight.
    # The door the character is breaking down takes the bar while there is
    # one.
    #
    # The name goes inside the bar in front of the count, because the label
    # outside it is two columns wide. A creature the character can see is
    # named by its species. One they have only made out as an outline is
    # named by how big it is.
    private def fought(game : Game) : Nil
      door = game.door_target
      return forced(game, door) if door

      creature = game.fought
      @fight.hidden = creature.nil?
      return unless creature

      name = Naming.creature creature, game.fought_regard
      @threat.show creature.hit_points, creature.max_hit_points,
        "#{name} #{creature.hit_points}/#{creature.max_hit_points}"
    end

    # The bar for the door the character is breaking down, at *spot*.
    #
    # It reads like a creature's bar, with the door's hit points over a
    # whole door's.
    private def forced(game : Game, spot : {Int32, Int32}) : Nil
      @fight.hidden = false

      left = game.floor.door_health spot[0], spot[1]
      whole = Floor::WOODEN_DOOR
      @threat.show left, whole, "door #{left}/#{whole}"
    end

    # How fast the character walks, as a share of a normal pace, and what
    # they do in melee in a turn.
    #
    # A haste or a slow is in the walking, and so is the body armor. The
    # damage rate is against the creature being fought, or against
    # `Combat::REFERENCE`, as the weapon's detail box says.
    private def written_pacing(game : Game) : Nil
      player = game.player
      against, _whom = Detail.target game

      @pacing.clear
      @pacing.put 0, "Walk", Palette.faint
      @pacing.put GOLD, "#{player.speed * 100 // player.stride}%", Palette.plain
      @pacing.put_right "#{Detail.dps player.per_turn(against)} dps", Palette.plain
    end

    # The noise bar: how many squares the character's recent noise carries.
    #
    # It is out of the loudest sound there is, and it falls as turns pass.
    # The row is hidden at zero.
    private def heard(game : Game) : Nil
      carried = game.noise
      @noisy.hidden = carried.zero?
      @noise.show carried, Noise::LOUDEST, "noise #{carried}"
    end

    # The five scores, with their names over them.
    private def written_scores(player : Player) : Nil
      @score_names.clear
      @scores.clear

      Attributes::Which.values.each_with_index do |which, index|
        @score_names.put index * 3, which.short, Palette.faint
        @scores.put index * 3, player.attributes[which].to_s.rjust(2), Palette.plain
      end
    end

    # The achievements under the scores, with the turn each was earned on.
    private def written_achievements(player : Player) : Nil
      earned = player.achievements
      @achieved.hidden = earned.empty?
      @achieved.clear
      @achieved.put 0, ACHIEVEMENTS, Palette.faint unless earned.empty?

      while @achievements.size < earned.size
        added = Line.new
        @achievements << added
        @scoring.body.add added
      end

      @achievements.each_with_index do |row, index|
        row.clear
        found = earned[index]?
        row.hidden = found.nil?
        next unless found

        row.put 0, found.name, Palette.plain
        row.put_right "turn #{found.turn}", Palette.faint
      end
    end

    # One row per slot: the slot word, the blessing mark, and the item's name.
    #
    # An empty quiver that remembers its kind says "no stones". The summary
    # counts the slots with something in them.
    private def written_slots(game : Game) : Nil
      filled = 0
      Slot.listed.each_with_index do |slot, index|
        row = @slots[index]
        item = game.player.in_slot slot
        memory = game.player.quiver_memory if slot.quiver?
        filled += 1 if item

        row.clear
        row.put 0, slot.short, Palette.faint

        unless item
          row.put NAME, memory ? "no #{memory.kind.plural}" : NOTHING, Palette.vacant
          next
        end

        marked row, MARK, item
        row.put NAME, Naming.short(game.lore, item), Palette[item].style
      end

      @worn.summary = filled.to_s
    end

    # The pack, one entry to a row: the letter it is carried under, the
    # blessing mark, the glyph and the name.
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
        row.put 0, letter.to_s, Palette.faint unless letterless?
        marked row, PACK_MARK, item
        row.put PACK_GLYPH, look.glyph.to_s, look.style
        row.put PACK_NAME, Naming.short(game.lore, item), look.style
      end

      @packed.summary = entries.size.to_s
    end

    # Writes the blessing mark of *item* at *column*, as the item menus draw
    # it. An item whose blessing is not worked out gets a blank cell.
    private def marked(row : Line, column : Int32, item : Item) : Nil
      mark = Palette.blessing item
      row.put column, mark.glyph.to_s, mark.style if mark
    end
  end
end
