require "json"
require "./game"

module Roguelike
  # What the character knows now, as one value.
  #
  # `Observation.of` builds one from a run. It holds nothing the character
  # has not perceived. A creature behind a wall is absent. A potion nobody
  # has drunk gives the colour it comes in this run and not what is in it. A
  # creature standing against light behind it gives its size and not its
  # species.
  #
  # The rule for what goes in is the rule `Ui` already follows. A fact a
  # pane, a readout or a tooltip writes is here. A fact none of them writes
  # is left out. `Regard` decides most of it, and every field below that
  # depends on distance reads it.
  #
  # There is one departure. `Ui` writes a creature's hit points in the threat
  # bar and in the examine pane. `Creature#condition` gives how hurt it is
  # and not the count, which is what `bots/PROTOCOL.md` section 5.1 asks for.
  #
  # It includes `JSON::Serializable`. A bot reads one line of JSON per turn
  # and never parses English.
  #
  # Taking one changes nothing. It reads `Game#sight`, which works out what
  # the character can see and remembers none of it, so `Game#fingerprint` is
  # the same before and after. A snapshot that wrote to `Knowledge` would
  # give a headless run and a replay of the same actions two different
  # hashes, and neither process would report it.
  #
  # The caller does the looking. `Game#look` is the one place anything gets
  # into `Knowledge`, and `Ui::Play#refresh` calls it before it draws. A
  # headless loop calls it after each action for the same reason. A caller
  # that does not call it gets a remembered map one turn behind what the
  # character can see.
  class Observation
    include JSON::Serializable

    # The character a row of the remembered map holds for a square nobody has
    # seen.
    #
    # No terrain is written with a space, so a blank square is never a
    # terrain the character has looked at.
    UNKNOWN = ' '

    # The character a row of the visible grid holds for a square in view.
    SHOWN = '1'

    # The character a row of the visible grid holds for a square out of view.
    HIDDEN = '0'

    # What a creature's hit points are divided by to be near death.
    #
    # A quarter of them or fewer. The threat bar shades from red to yellow
    # over that range as a creature falls.
    NEAR_DEATH = 4

    # How hurt a creature is, as far as the character can tell.
    enum Health
      # It has taken nothing.
      Unhurt

      # It has taken something and has more than a quarter of its hit points
      # left.
      Wounded

      # It is about to fall.
      NearDeath

      # How hurt *creature* is.
      def self.of(creature : Monster) : Health
        most = creature.max_hit_points
        return Unhurt if most <= 0

        left = creature.hit_points
        return Unhurt if left >= most
        return NearDeath if left * NEAR_DEATH <= most

        Wounded
      end
    end

    # Something working on the character that they have been told about.
    #
    # How long each lasts is not here. Nothing on the screen says it. The
    # character is told a thing started and told again when it wears off.
    enum Status
      # They cannot see.
      Blind

      # Something is hurrying them.
      Hurried

      # Something is holding them back.
      Dragging
    end

    # One grid of characters, one string per row.
    #
    # The remembered map and the visible grid are both this shape. Strings
    # are read by a person debugging and turned into an array by a harness.
    record Grid, width : Int32, height : Int32, rows : Array(String) do
      include JSON::Serializable
    end

    # The character, as the sidebar writes them.
    class Character
      include JSON::Serializable

      # Where they stand.
      getter pos : {Int32, Int32}

      # What they have left, and what they have when they are whole.
      getter hit_points : Int32
      getter max_hit_points : Int32

      # How far they have got.
      getter level : Int32
      getter experience : Int32

      # What an attack on them is reduced by.
      getter armour_class : Int32

      # What they are carrying in coins.
      getter gold : Int32

      # Their five scores.
      getter attributes : Attributes

      # What is working on them now.
      getter statuses : Array(Status)

      def initialize(@pos : {Int32, Int32}, @hit_points : Int32,
                     @max_hit_points : Int32, @level : Int32,
                     @experience : Int32, @armour_class : Int32,
                     @gold : Int32, @attributes : Attributes,
                     @statuses : Array(Status))
      end

      # The block for *player*.
      def self.of(player : Player) : Character
        statuses = [] of Status
        statuses << Status::Blind if player.blind?
        statuses << Status::Hurried if player.pace.hurried?
        statuses << Status::Dragging if player.pace.dragging?

        new pos: player.at,
          hit_points: player.hit_points,
          max_hit_points: player.max_hit_points,
          level: player.level,
          experience: player.experience,
          armour_class: player.armour_class,
          gold: player.gold,
          attributes: player.attributes,
          statuses: statuses
      end
    end

    # One creature the character can see.
    #
    # A creature they cannot see is not one of these. A creature they make
    # out only as a shape gives its size, and its species, how hurt it is and
    # what it is doing all wait for light on it.
    class Creature
      include JSON::Serializable

      # The id the run gave it. `Game#monster` finds it again.
      getter id : Int32

      # Where it stands.
      getter pos : {Int32, Int32}

      # How well the character has made it out.
      getter regard : Regard

      # How big it is. A shape gives this much.
      getter size : Size

      # What sort of creature it is. `nil` for a shape.
      getter species : Species?

      # What the character calls it. Its species, or the size of the shape.
      getter name : String

      # How hurt it is. `nil` for a shape.
      getter condition : Health?

      # What it is doing. `nil` for a shape.
      getter awareness : Awareness?

      def initialize(@id : Int32, @pos : {Int32, Int32}, @regard : Regard,
                     @size : Size, @name : String, @species : Species? = nil,
                     @condition : Health? = nil, @awareness : Awareness? = nil)
      end

      # What the character has made out of *creature*, at *regard*.
      def self.of(floor : Floor, creature : Monster, regard : Regard) : Creature
        size = creature.species.size
        return new(id: creature.id, pos: creature.at, regard: regard,
          size: size, name: size.label) unless regard.everything?

        new id: creature.id,
          pos: creature.at,
          regard: regard,
          size: size,
          name: creature.label,
          species: creature.species,
          condition: Health.of(creature),
          awareness: floor.awareness(creature)
      end
    end

    # One item the character has made out.
    #
    # One class serves the pack, the floor and the map. `#letter` and
    # `#slot` are filled for one the character carries, `#pos` for one lying
    # on a square, and `#last_seen_turn` as well for one they remember lying
    # there. A field that does not apply is `nil` and is left out of the
    # JSON.
    #
    # Every field that depends on distance reads `#regard`. Short of
    # `Regard::Everything` the character has made out the class of the thing
    # and no more, so the kind of a disguised item, its appearance, its
    # blessing, its condition and its enchantment are all absent.
    class Seen
      include JSON::Serializable

      # The id the run gave it. `Game#item` finds it again.
      getter id : Int32

      # What the character calls it. `Lore#name` writes it.
      getter name : String

      # What sort of thing it is. A bottle is a potion from any distance.
      getter item_class : ItemClass

      # How many there are.
      getter count : Int32

      # How well the character has made it out.
      getter regard : Regard

      # Whether the character knows what this is.
      #
      # True exactly when `#kind` is given. A kind nobody has to find out is
      # known from the start, and a disguised kind is known once somebody has
      # drunk, read or zapped one and is standing near enough to read the
      # label on this one.
      getter? identified : Bool

      # Which kind it is. `nil` while the character cannot tell.
      getter kind : ItemKind?

      # What its kind looks like this run. `nil` for a kind nobody has to
      # find out, for one the character has found out, and for a thing too
      # far off to read.
      getter appearance : String?

      # Whether a god has touched it. `nil` while the character does not
      # know.
      getter blessing : Blessing?

      # How well it was made. `nil` short of a kind the character knows.
      getter condition : Condition?

      # What it adds to a roll. `nil` short of a kind the character knows.
      getter enchantment : Int32?

      # How many uses a wand has left. `nil` for anything else.
      getter charges : Int32?

      # Whether it is alight.
      getter? lit : Bool

      # Which letter it is carried under. `nil` for one on the floor.
      #
      # A string of one character. `Char` has no JSON writer, and
      # `Inventory::Slot` writes a letter as a string for the same reason.
      getter letter : String?

      # Which slot holds it. `nil` for one in the pack and one on the floor.
      getter slot : Slot?

      # Which square it lies on. `nil` for one the character carries.
      getter pos : {Int32, Int32}?

      # Which turn it was last seen on. `nil` for one in view now and one the
      # character carries.
      getter last_seen_turn : Int32?

      def initialize(@id : Int32, @name : String, @item_class : ItemClass,
                     @count : Int32, @regard : Regard, @identified : Bool,
                     @lit : Bool, @kind : ItemKind? = nil,
                     @appearance : String? = nil, @blessing : Blessing? = nil,
                     @condition : Condition? = nil,
                     @enchantment : Int32? = nil, @charges : Int32? = nil,
                     @letter : String? = nil, @slot : Slot? = nil,
                     @pos : {Int32, Int32}? = nil,
                     @last_seen_turn : Int32? = nil)
      end

      # What the character has made out of *item*, at *regard*.
      def self.of(lore : Lore, item : Item, regard : Regard,
                  letter : String? = nil, slot : Slot? = nil,
                  pos : {Int32, Int32}? = nil,
                  last_seen_turn : Int32? = nil) : Seen
        unless regard.everything?
          return bare lore, item, regard, letter, slot, pos, last_seen_turn
        end

        kind = item.kind
        known = lore.known? kind

        new id: item.id,
          name: lore.name(item),
          item_class: kind.item_class,
          count: item.count,
          regard: regard,
          identified: known,
          lit: item.lit?,
          kind: known ? kind : nil,
          appearance: known ? nil : lore.appearance(kind),
          blessing: item.blessing_known? ? item.blessing : nil,
          condition: known ? item.condition : nil,
          enchantment: known ? item.enchantment : nil,
          charges: item.charges,
          letter: letter,
          slot: slot,
          pos: pos,
          last_seen_turn: last_seen_turn
      end

      # What the character has made out of *item* from too far off to read
      # it.
      #
      # The class of the thing and how many there are. A kind nobody has to
      # find out is named as well, because a spear is a spear across a hall.
      # A potion, a wand and a scroll are a bottle, a stick and a sheet until
      # somebody stands near enough to read the label, so none of the three
      # is named here and neither is anything written on it.
      private def self.bare(lore : Lore, item : Item, regard : Regard,
                            letter : String?, slot : Slot?,
                            pos : {Int32, Int32}?,
                            last_seen_turn : Int32?) : Seen
        kind = item.kind
        plain = !kind.disguised?

        new id: item.id,
          name: lore.name(item, regard: regard),
          item_class: kind.item_class,
          count: item.count,
          regard: regard,
          identified: plain,
          lit: item.lit?,
          kind: plain ? kind : nil,
          letter: letter,
          slot: slot,
          pos: pos,
          last_seen_turn: last_seen_turn
      end
    end

    # One fitting standing on one square.
    #
    # A fixture is part of the room. It is never picked up and never moves,
    # so one list holds both the fittings in view and the ones the character
    # remembers. `#last_seen_turn` is `nil` for one in view.
    #
    # `Ui::MapPane` draws a fitting over the terrain, in view and remembered
    # both, and `Ui::Detail.about` writes its name and a sentence about it at
    # any distance. So nothing here depends on `Regard`.
    class Fitting
      include JSON::Serializable

      # Which square it stands on.
      getter pos : {Int32, Int32}

      # What sort of fitting it is.
      getter kind : FixtureKind

      # What the character calls it. `Fixture#label` writes it.
      getter name : String

      # Whether it is alight.
      getter? lit : Bool

      # Whether it is bolted to a wall.
      #
      # A bolted one throws its whole radius and one standing on its own foot
      # throws one square less. Which wall it is bolted to is not here.
      # `Ui::Detail` writes "An iron bracket on the wall" or "An iron stand"
      # and names no direction.
      getter? mounted : Bool

      # Which turn it was last seen on. `nil` for one in view now.
      getter last_seen_turn : Int32?

      def initialize(@pos : {Int32, Int32}, @kind : FixtureKind,
                     @name : String, @lit : Bool, @mounted : Bool,
                     @last_seen_turn : Int32? = nil)
      end

      # What the character has made out of *fitting* standing on *spot*.
      def self.of(fitting : Fixture, spot : {Int32, Int32},
                  last_seen_turn : Int32? = nil) : Fitting
        new pos: spot,
          kind: fitting.kind,
          name: fitting.label,
          lit: fitting.lit?,
          mounted: fitting.mounted?,
          last_seen_turn: last_seen_turn
      end
    end

    # One item the character remembers lying somewhere, while the list is
    # being built.
    private record Lying,
      spot : {Int32, Int32},
      item : Item,
      turn : Int32,
      regard : Regard

    # Which turn the run is on.
    getter turn : Int32

    # Which floor the character is on.
    getter floor : String

    # The character.
    getter player : Character

    # The floor as the character remembers it, one string per row.
    #
    # Each square holds `Terrain#mark`, the character a floor file and a save
    # file write that terrain with. A square nobody has seen holds `UNKNOWN`.
    #
    # `Ui::MapPane` draws the same squares. It draws all three rocks as one
    # glyph and both floors as another, and tells them apart by colour. This
    # keeps the terrain, so a bot tells a dirt floor from a stone one with no
    # colour to read.
    getter map : Grid

    # Which squares are in view now, one string per row.
    #
    # `SHOWN` for a square the character can see, `HIDDEN` for one they
    # cannot. A square in the map and not here is remembered rather than
    # seen, and what is drawn on it may be out of date.
    getter visible : Grid

    # What the character carries, one entry per letter.
    getter inventory : Array(Seen)

    # Every creature the character can see, nearest first.
    getter monsters : Array(Creature)

    # Every item lying on a square the character can see, nearest first.
    #
    # Every item of every pile in view, and not the top one of each alone.
    # `Ui::NearbyPane` lists the same items.
    getter items : Array(Seen)

    # Every item the character remembers lying on a square out of view,
    # nearest first.
    #
    # One per square. A memory holds the top of the pile, which is the one
    # the map draws.
    getter remembered_items : Array(Seen)

    # Every fitting the character can see or remembers, nearest first.
    #
    # A sconce is the light the floor comes with. `Game#lights` reads the
    # fittings before anything else, so where they stand and which of them
    # are alight is most of what decides what the character can see.
    getter fixtures : Array(Fitting)

    def initialize(@turn : Int32, @floor : String, @player : Character,
                   @map : Grid, @visible : Grid, @inventory : Array(Seen),
                   @monsters : Array(Creature), @items : Array(Seen),
                   @remembered_items : Array(Seen),
                   @fixtures : Array(Fitting))
    end

    # What the character knows about *game* now.
    #
    # This works out what they can see once and builds every list from it.
    # `Game#item` and `Game#monster` walk the whole run on each call, so
    # nothing here looks an id up.
    #
    # `Game#sight` rather than `Game#look`. Nothing here writes to the run.
    #
    # `Player#knowledge?` rather than `Game#knowledge` for the same reason.
    # `Game#knowledge` puts an empty `Knowledge` in the character's table for
    # a floor they have not looked at yet, and that reaches the save and the
    # fingerprint. `Player#knowledge?` answers `nil` and stores nothing.
    def self.of(game : Game) : Observation
      of game, game.sight
    end

    # :ditto:, against a field of view that has already been worked out.
    #
    # Working out a field of view is most of what a turn on a large floor
    # costs. A caller that has just called `Game#look` holds the vision it
    # answered, and passing it here is one cast a turn rather than two.
    # `Game#monsters_in_sight` takes one the same way.
    def self.of(game : Game, seen : Vision) : Observation
      ground = game.floor
      known = game.player.knowledge?(ground.id) || Knowledge.new(ground.id)

      new turn: game.turn,
        floor: ground.id,
        player: Character.of(game.player),
        map: Grid.new(ground.columns, ground.rows,
          known.to_map(ground, UNKNOWN)),
        visible: Grid.new(ground.columns, ground.rows,
          visible_rows(ground, seen)),
        inventory: carried(game),
        monsters: creatures(game, seen),
        items: litter(game, seen),
        remembered_items: recalled(game, known, seen),
        fixtures: fittings(game, known, seen)
    end

    # The visible grid over *ground*, from *seen*.
    #
    # `Vision#each` yields the squares in view, so this touches those rather
    # than every square of the floor.
    private def self.visible_rows(ground : Floor, seen : Vision) : Array(String)
      rows = Array.new(ground.rows) { Array.new(ground.columns, HIDDEN) }

      seen.each do |spot|
        next unless ground.contains? spot[0], spot[1]

        rows[spot[1]][spot[0]] = SHOWN
      end

      rows.map &.join
    end

    # What the character carries, one entry per letter.
    #
    # `Game#carried` counts everything under a letter as one stack, which is
    # what the sidebar writes. Twelve arrows and three more that differ only
    # in a hidden curse are fifteen arrows. The id is the first stack's.
    private def self.carried(game : Game) : Array(Seen)
      found = [] of Seen

      game.player.inventory.each do |letter, _|
        item = game.carried letter
        next unless item

        found << Seen.of(game.lore, item, Regard::Everything,
          letter: letter.to_s, slot: game.slot_of(letter))
      end

      found
    end

    # Every creature the character can see, nearest first.
    private def self.creatures(game : Game, seen : Vision) : Array(Creature)
      ground = game.floor
      here = game.player.at
      found = [] of Creature

      ground.each_monster do |_column, _row, creature|
        regard = game.regard_of creature, seen
        next unless regard.made_out?

        found << Creature.of(ground, creature, regard)
      end

      found.sort_by! { |creature| order here, creature.pos }
    end

    # Every item lying on a square the character can see, nearest first.
    private def self.litter(game : Game, seen : Vision) : Array(Seen)
      ground = game.floor
      here = game.player.at
      spots = [] of {Int32, Int32}

      ground.each_pile do |column, row, _pile|
        spots << {column, row} if seen.includes? column, row
      end

      spots.sort_by! { |spot| order here, spot }
      found = [] of Seen

      spots.each do |spot|
        regard = game.regard_of_item spot[0], spot[1], seen

        ground.items(spot[0], spot[1]).each do |item|
          found << Seen.of(game.lore, item, regard, pos: spot)
        end
      end

      found
    end

    # Every item the character remembers lying on a square out of view,
    # nearest first.
    private def self.recalled(game : Game, known : Knowledge,
                              seen : Vision) : Array(Seen)
      here = game.player.at
      found = [] of Lying

      known.each do |column, row, memory|
        item = memory.item
        next unless item
        next unless memory.regard.made_out?
        next if seen.includes? column, row

        found << Lying.new({column, row}, item, memory.turn, memory.regard)
      end

      found.sort_by! { |lying| order here, lying.spot }
      found.map do |lying|
        Seen.of game.lore, lying.item, lying.regard,
          pos: lying.spot, last_seen_turn: lying.turn
      end
    end

    # Every fitting the character can see or remembers, nearest first.
    #
    # A fitting in view is what stands there now. One out of view is what the
    # character last saw, which says whether it was alight then and not
    # whether it is alight now. A fixture never moves, so the two never name
    # the same square twice.
    private def self.fittings(game : Game, known : Knowledge,
                              seen : Vision) : Array(Fitting)
      ground = game.floor
      here = game.player.at
      found = [] of Fitting

      ground.each_fixture do |column, row, fitting|
        next unless seen.includes? column, row

        found << Fitting.of(fitting, {column, row})
      end

      known.each do |column, row, memory|
        fitting = memory.fixture
        next unless fitting
        next if seen.includes? column, row

        found << Fitting.of(fitting, {column, row}, memory.turn)
      end

      found.sort_by! { |fitting| order here, fitting.pos }
    end

    # How far *there* is from *here*, and which of two equally far squares
    # comes first.
    #
    # The squared distance, then the row, then the column.
    # `Ui::NearbyPane.order` sorts its list the same way. The model does not
    # read `Ui`, so the rule is written in both.
    private def self.order(here : {Int32, Int32},
                           there : {Int32, Int32}) : {Int32, Int32, Int32}
      across = there[0] - here[0]
      down = there[1] - here[1]

      {across * across + down * down, there[1], there[0]}
    end

    def to_s(io : IO) : Nil
      io << "Observation(turn " << @turn << ' ' << @floor
      io << ' ' << @monsters.size << " seen)"
    end
  end
end
