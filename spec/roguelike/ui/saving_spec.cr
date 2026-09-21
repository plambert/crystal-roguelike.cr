require "../../spec_helper"

Spectator.describe "when a run is written to the store" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Save = Roguelike::Save

  # One lit room, the character on the up staircase and the way down beside
  # it.
  ROOM = [
    "#####",
    "#.>.#",
    "#.<.#",
    "#####",
  ]

  # The same with an orc in it, for a run that ends in a death.
  FIGHT = [
    "#####",
    "#.o.#",
    "#.<.#",
    "#####",
  ]

  # How many swings a spec takes before it gives up waiting for one to land.
  SWINGS = 200

  # A named run, saved to *store*.
  def playing(store : Save::Store? = nil, name : String = "Sparky",
              map : Array(String) = ROOM, hit_points : Int32? = nil) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", map)
    player = Roguelike::Player.new floor.id, *Roguelike::Game.entrance(floor),
      hit_points: hit_points
    player.name = name

    game = Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {floor.id => floor}), player)

    Playing.open game, 80, 24, store: store
  end

  # The game saved as *name* in *store*, or a failure saying there is none.
  def saved(store : Save::Store, name : String = "Sparky") : Roguelike::Game
    found = store.read name
    raise "#{store.directory} holds no character called #{name}" unless found

    found
  end

  # The most recently ended character in *held*, or a failure saying there is
  # none.
  def retired(held : Array(Save::Held)) : Save::Held
    found = held.first?
    raise "no character has ended" unless found

    found
  end

  describe "carrying a character on" do
    # A run whose log is far longer than the pane, written out and read back.
    def carried_on(lines : Int32 = 40) : Playing::Run
      store = Playing.store
      first = playing store
      lines.times { |written| first.game.say "Line number #{written}." }
      first.play.keep

      later = Playing.open nil, 80, 24, store: store
      later.play.play_as "Sparky"
      later
    end

    # The log comes back whole. The person read it in the session that wrote
    # it, so none of it waits behind `--More--`.
    it "does not page through the history that came back with it" do
      run = carried_on

      expect(run.pager.holding?).to be_false
      expect(run.text).not_to contain "--More--"
    end

    it "counts every restored line as read" do
      run = carried_on

      expect(run.pager.unread).to eq 0
    end

    it "shows the newest lines rather than the oldest" do
      run = carried_on

      expect(run.pager.showing.last).to contain "Welcome back, Sparky."
    end

    it "gives the keyboard back to the game" do
      run = carried_on
      before = run.at

      run.press "h"

      expect(run.at).not_to eq before
    end

    # A run written before anything filled the log still reads as a run.
    it "holds nothing when the log is short" do
      run = carried_on 1

      expect(run.pager.holding?).to be_false
    end
  end

  describe "#keep" do
    it "writes the run" do
      store = Playing.store
      run = playing store

      run.play.keep

      expect(store.holds? "Sparky").to be_true
    end

    # A run holds no name until the title screen has been answered. A file
    # called nothing helps nobody.
    it "writes nothing for a character nobody has named" do
      store = Playing.store
      run = playing store, name: ""

      run.play.keep

      expect(store.characters).to be_empty
    end

    it "writes nothing when there is no store" do
      run = playing

      run.play.keep

      expect(run.store).to be_nil
    end

    # Losing the turn a person is playing because a disk is full is worse
    # than losing the save.
    it "says so in the log rather than stopping the run" do
      store = Save::Store.under Path["/proc/nowhere/roguelike"]
      run = playing store

      run.play.keep

      expect(run.said).to contain "could not be saved"
      expect(run.finished?).to be_false
    end
  end

  describe "when it happens" do
    it "writes on the way down a staircase" do
      store = Playing.store
      run = playing store
      run.press "k"

      run.press ">"

      expect(retired(store.won).outcome.won?).to be_true
    end

    it "writes on the way out of the dungeon" do
      store = Playing.store
      run = playing store

      run.press "<"
      run.press "y"

      expect(retired(store.won).outcome.left?).to be_true
    end

    it "writes when the person quits" do
      store = Playing.store
      run = playing store
      run.press "l"

      run.press "Q"
      run.press "y"

      expect(saved(store).turn).to eq 1
    end

    it "writes nothing when the person changes their mind about quitting" do
      store = Playing.store
      run = playing store

      run.press "Q"
      run.press "n"

      expect(store.characters).to be_empty
    end

    it "writes when the character dies" do
      store = Playing.store
      run = playing store, map: FIGHT, hit_points: 1

      SWINGS.times do
        break if run.game.over?

        run.press "k"
      end

      expect(run.game.outcome.died?).to be_true
      expect(retired(store.died).outcome.died?).to be_true
    end
  end

  describe "a run that is over" do
    # A dead character is not a character to carry on. Their file goes where
    # it can be read and their name goes back to whoever wants it.
    it "is taken out of the saves" do
      store = Playing.store
      run = playing store, map: FIGHT, hit_points: 1

      SWINGS.times do
        break if run.game.over?

        run.press "k"
      end

      expect(store.holds? "Sparky").to be_false
      expect(store.characters).to be_empty
    end

    it "is kept among the deaths" do
      store = Playing.store
      run = playing store, map: FIGHT, hit_points: 1

      SWINGS.times do
        break if run.game.over?

        run.press "k"
      end

      expect(store.died.map &.name).to eq ["Sparky"]
      expect(retired(store.died).turn).to eq run.game.turn
      expect(store.won).to be_empty
    end

    it "leaves the name free for somebody new" do
      store = Playing.store
      run = playing store
      run.press "<"
      run.press "y"

      again = playing store, name: ""
      again.play.play_as "Sparky"

      expect(again.play.entry.asking?).to be_false
      expect(again.game.player.name).to eq "Sparky"
      expect(store.holds? "Sparky").to be_true
    end

    # One name can end many times, and every ending is kept.
    it "keeps an earlier ending under the same name" do
      store = Playing.store

      2.times do
        run = playing store
        run.press "<"
        run.press "y"
      end

      expect(store.won.size).to eq 2
      expect(store.won.map &.name).to eq ["Sparky", "Sparky"]
    end
  end

  describe "carrying a character on" do
    it "plays the game that was written rather than the one that was dug" do
      store = Playing.store
      kept = playing store
      kept.press "k"
      kept.play.keep

      run = playing store, name: ""
      run.play.play_as "Sparky"

      expect(run.game.turn).to eq 1
      expect(run.game.player.name).to eq "Sparky"
    end

    it "keeps what the character was carrying" do
      store = Playing.store
      kept = playing store
      kept.game.player.inventory.add Item.new(Kind::LongSword, enchantment: 1)
      kept.game.wield 'a'
      kept.play.keep

      run = playing store, name: ""
      run.play.play_as "Sparky"

      expect(run.game.player.wielded.try &.kind).to eq Kind::LongSword
    end

    # The floor this run was built on is thrown away, so the map pane has to
    # be pointed at the floor the saved character is standing on.
    it "draws the floor the character is on" do
      store = Playing.store
      kept = playing store
      kept.press "k"
      kept.play.keep

      run = playing store, name: ""
      run.play.play_as "Sparky"
      run.render

      expect(run.map.floor.id).to eq run.game.player.floor
      expect(run.map.floor).to be run.game.floor
    end

    # A name that would be written over somebody else is refused, so the
    # question goes back up rather than the run starting.
    it "refuses a name that would write over somebody else" do
      store = Playing.store
      kept = playing store, name: "Sparky the Bold"
      kept.play.keep

      run = playing store, name: ""
      run.play.play_as "Sparky!the!Bold"

      expect(run.play.entry.asking?).to be_true
      expect(run.game.player.name).to eq ""
      expect(store.characters.map &.name).to eq ["Sparky the Bold"]
    end

    it "starts a run under a name the store has not got" do
      store = Playing.store
      run = playing store, name: ""

      run.play.play_as "Nobody"

      expect(run.game.player.name).to eq "Nobody"
      expect(run.game.turn).to eq 0
      expect(store.holds? "Nobody").to be_true
    end
  end
end
