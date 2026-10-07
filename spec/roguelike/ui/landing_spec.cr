require "../../spec_helper"

Spectator.describe "showing a shot once it has landed" do
  alias Action = Roguelike::Action
  alias Awareness = Roguelike::Awareness
  alias Creature = Roguelike::Kind
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Palette = Roguelike::Ui::Palette
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # One lit hall with the character at the west end and room to shoot east.
  HALL = [
    "############",
    "#<.........#",
    "############",
  ]

  # A wider hall, for more than one creature to shoot down.
  WIDE = [
    "##############",
    "#............#",
    "#<...........#",
    "#............#",
    "##############",
  ]

  # Where the character stands in each.
  HERE   = {1, 1}
  MIDDLE = {1, 2}

  # The character's hit points. Enough that only one example is about dying.
  PLENTY = 500

  # A game on *rows* with the character at *here* holding *items*, and
  # *creatures* on the floor awake and hunting them.
  def hall(items : Array(Item) = [] of Item,
           creatures : Array(Monster) = [] of Monster,
           rows : Array(String) = HALL,
           here : {Int32, Int32} = HERE,
           hit_points : Int32 = PLENTY) : Game
    floor = Playing.daylight Floor.parse("hall", rows)
    creatures.each { |creature| floor.place creature }

    player = Player.new "hall", *here, hit_points: hit_points
    items.each { |item| player.inventory.add item }

    game = Game.new World.new(Playing::SEED, {"hall" => floor}), player
    creatures.each { |creature| hunting game, creature }
    game
  end

  # Wakes the band *creature* belongs to and tells it the floor and where
  # the character stands.
  def hunting(game : Game, creature : Monster) : Nil
    band = game.floor.band(creature.band) || raise "the floor has lost the band"
    knowledge = band.knowledge game.floor.id
    game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
    knowledge.saw Knowledge::PLAYER, game.player.x, game.player.y, game.turn
    band.awareness = Awareness::Hunting
  end

  # A goblin standing at *at*, asleep.
  def goblin(at : {Int32, Int32}) : Monster
    Monster.new Species::Goblin, at[0], at[1], "band-#{at[0]}", hit_points: 200
  end

  # An orc archer at *at* with a bow and *arrows* arrows.
  def archer(at : {Int32, Int32}, arrows : Int32 = 20) : Monster
    creature = Monster.new Creature::OrcArcher, at[0], at[1], "archers", hit_points: PLENTY
    creature.outfit [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: arrows)]
    creature
  end

  # A goblin scout at *at* with a sling and *stones* stones.
  def scout(at : {Int32, Int32}, stones : Int32 = 20) : Monster
    creature = Monster.new Creature::GoblinScout, at[0], at[1], "scouts", hit_points: PLENTY
    creature.outfit [Item.new(Kind::Sling), Item.new(Kind::Stone, count: stones)]
    creature
  end

  # The bow and the arrows the character shoots with.
  def bow : Array(Item)
    [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 12)]
  end

  # The id of what *game*'s character carries under *letter*.
  def id_under(game : Game, letter : Char) : Int32
    game.carried(letter).try(&.id) || raise "nothing is under #{letter}"
  end

  # A run with a bow readied, arrows in the quiver and *monsters* placed
  # after the turns readying costs, on a clock a spec fires by hand.
  def bowman(monsters : Array(Monster) = [] of Monster, clock : Bool = true,
             rows : Int32 = 24) : Playing::Run
    run = Playing.open hall(bow), 80, rows, clock: clock
    run.press "w", "a"
    run.press "w", "b"

    monsters.each { |creature| run.game.floor.place creature }
    run.play.refresh
    run.render
    run
  end

  # Presses `.` until a creature shoots, and answers whether one did. The
  # shot is left in the air.
  def wait_for_a_shot(run : Playing::Run, most : Int32 = 6) : Bool
    most.times do
      run.press "."
      return true unless run.game.flights.empty?

      run.run_timers
    end

    false
  end

  # The square the missile is drawn on, or `nil` when none is.
  def missile_at(run : Playing::Run) : {Int32, Int32}?
    run.map.marks.each_key do |spot|
      return spot unless spot == run.at
    end

    nil
  end

  # The glyph drawn on the floor's *x*, *y*.
  def glyph_at(run : Playing::Run, x : Int32, y : Int32) : Char
    spot = run.map.screen_of(x, y) || raise "#{x}, #{y} is off the screen"
    run.rows[spot[1]][spot[0]]
  end

  # What the pane says, as one string.
  def shown(run : Playing::Run) : String
    run.pager.showing.join ' '
  end

  # What the log says about the arrow and the goblin, once the shot is over.
  LANDED = /arrow (hits|misses) the goblin warrior/

  # The goblin's bar on the sidebar. The sidebar clips the name and the
  # count to the bar's width.
  FOUGHT = /vs .*warrior \d+\//

  describe "the character's arrow" do
    it "is said to hit or miss only once it has landed" do
      run = bowman [goblin({6, 1})]
      run.press "f"
      run.press "Enter"

      expect(run.log.join " ").to match LANDED
      expect(shown run).not_to match LANDED
      expect(shown run).not_to contain "You shoot"
      expect(missile_at run).to eq({2, 1})

      run.run_timers

      expect(shown run).to contain "You shoot an arrow."
      expect(shown run).to match LANDED
      expect(missile_at run).to be_nil
    end

    # The sidebar shows the bar for the creature being fought only in a
    # window tall enough for it.
    it "puts the goblin on the sidebar only once it has landed" do
      run = bowman [goblin({6, 1})], rows: 40
      run.press "f"
      run.press "Enter"

      expect(run.game.fought).not_to be_nil
      expect(run.text).not_to match FOUGHT

      run.run_timers

      expect(run.text).to match FOUGHT
    end

    it "is drawn lying on the floor only once it has landed" do
      run = bowman
      run.press "f"
      5.times { run.press "l" }
      run.press "Enter"

      expect(run.game.floor.items(6, 1).map &.kind).to contain Kind::Arrow
      expect(glyph_at run, 6, 1).to eq '.'

      run.run_timers

      expect(glyph_at run, 6, 1).to eq Palette.flying(Item.new Kind::Arrow).glyph
    end

    it "lands at once when there is no clock" do
      run = bowman [goblin({6, 1})], clock: false, rows: 40
      run.press "f"
      run.press "Enter"

      expect(shown run).to match LANDED
      expect(run.text).to match FOUGHT
      expect(missile_at run).to be_nil
    end
  end

  describe "a creature's arrow" do
    it "is drawn crossing the floor from the creature" do
      run = Playing.open hall(creatures: [archer({7, 1})]), 80, 24, clock: true

      expect(wait_for_a_shot run).to be_true
      expect(run.game.events.any? Event::Shot).to be_true
      expect(missile_at run).to eq({6, 1})
    end

    it "is said to have been shot only once it has landed" do
      run = Playing.open hall(creatures: [archer({7, 1})]), 80, 24, clock: true
      wait_for_a_shot run

      expect(run.said).to match /The arrow (hits you|misses you)/
      expect(shown run).not_to contain "shoots"

      run.run_timers

      expect(shown run).to contain "The orc archer shoots an arrow at you from the east."
      expect(shown run).to match /The arrow (hits you|misses you)/
    end

    it "takes the hit points off the sidebar only once it has landed" do
      run = Playing.open hall(creatures: [archer({7, 1})]), 80, 24, clock: true
      wait_for_a_shot run

      expect(run.text).to match /HP\s+#{PLENTY}\//

      run.run_timers

      expect(run.text).to match /HP\s+#{run.game.player.hit_points}\//
    end
  end

  # Two archers of one band, one on each side of the character's row. Two of
  # another species would fight each other instead.
  describe "two creatures shooting in one turn" do
    it "fly one after the other, and each is said to have shot once it has landed" do
      run = Playing.open hall(creatures: [archer({7, 1}), archer({7, 3})],
        rows: WIDE, here: MIDDLE), 80, 24, clock: true

      expect(wait_for_a_shot run).to be_true
      flights = run.game.flights
      expect(flights.size).to eq 2
      expect(flights[0].shooter).not_to eq flights[1].shooter
      expect(shown(run).scan("shoots").size).to eq 0

      flights[0].flight.path.size.times { run.tick }

      expect(shown(run).scan("shoots").size).to eq 1
      expect(missile_at run).to eq flights[1].flight.path.first

      fired = run.run_timers

      expect(fired).to eq flights[1].flight.path.size
      expect(shown(run).scan("shoots").size).to eq 2
      expect(missile_at run).to be_nil
    end
  end

  describe "a death by arrow" do
    it "puts the ending up only once the arrow has landed" do
      run = Playing.open hall(creatures: [archer({7, 1})], hit_points: 1),
        80, 24, clock: true

      40.times do
        run.press "."
        break if run.game.over?

        run.run_timers
      end

      expect(run.game.over?).to be_true
      expect(run.game.flights).not_to be_empty
      expect(run.placard.showing?).to be_false

      run.run_timers

      expect(run.placard.showing?).to be_true
    end
  end

  describe "a key pressed while a shot is in the air" do
    it "takes its turn and draws the run as it stands" do
      run = bowman [goblin({6, 1})]
      run.press "f"
      run.press "Enter"
      run.tick

      run.press "."

      expect(missile_at run).to be_nil
      expect(run.map.frozen).to be_nil
      expect(shown run).to match LANDED
      expect(run.run_timers).to eq 0
    end
  end

  describe "the run" do
    # The same keys on *run*: a shot, a wait drawn to the end, a wait cut
    # short by the next key, and a wait drawn to the end.
    def played(run : Playing::Run) : Playing::Run
      run.press "f"
      run.press "Enter"
      run.run_timers
      run.press "."
      run.run_timers
      run.press "."
      run.press "."
      run.run_timers
      run
    end

    it "ends up where a run drawn with no clock does" do
      drawn = played bowman [goblin({6, 1})]
      undrawn = played bowman [goblin({6, 1})], clock: false

      expect(drawn.game.fingerprint).to eq undrawn.game.fingerprint
      expect(drawn.log).to eq undrawn.log
    end

    # The screen looks at the floor after every action, which is what fills
    # in the character's map, so the run with no screen looks the same way.
    it "ends up where a run with no screen does" do
      drawn = played bowman [goblin({6, 1})]

      plain = hall bow
      plain.enroll
      plain.look
      plain.perform Action::Wield.new(id_under(plain, 'a'))
      plain.look
      plain.perform Action::Wield.new(id_under(plain, 'b'))
      plain.look
      plain.floor.place goblin({6, 1})
      plain.perform Action::Fire.new({6, 1})
      plain.look
      3.times do
        plain.perform Action::Wait.new
        plain.look
      end

      expect(drawn.game.fingerprint).to eq plain.fingerprint
      expect(drawn.log.reject(&.starts_with? "Aim with")).to eq plain.log.lines
    end
  end
end
