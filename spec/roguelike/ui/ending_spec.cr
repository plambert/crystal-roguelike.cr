require "../../spec_helper"

Spectator.describe "how a run starts and ends" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Outcome = Roguelike::Outcome
  alias Placards = Roguelike::Ui::Placards
  alias Species = Roguelike::Species

  # The seed every example here runs on. A failure names a run somebody can
  # start.
  SEED = 20260915_u64

  # The window both screens are drawn in. A fixture is the size it was drawn
  # at, so this is fixed rather than taken from the default.
  WINDOW = {72, 24}

  # One lit room, the character on the up staircase, an orc beside them, and
  # the way down in the corner.
  ROOM = [
    "#########",
    "#..o....#",
    "#..<...>#",
    "#########",
  ]

  # A run on `ROOM` with *hit_points*, carrying a few things.
  #
  # The pack holds something readied, something stacked and something the
  # character never found out, so the end screen names one of each.
  #
  # The sword is put in the hand rather than wielded. `Game#wield` spends a
  # turn, and a turn spent here is one the orc gets before the screen the
  # example is about goes up.
  def playing(hit_points : Int32? = nil, title : Bool = false,
              store : Roguelike::Save::Store? = nil) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
    player = Roguelike::Player.new floor.id, *Roguelike::Game.entrance(floor)
    player.hurt player.hit_points - hit_points if hit_points

    game = Roguelike::Game.new(
      Roguelike::World.new(SEED, {floor.id => floor}), player,
      lore: Roguelike::Lore.roll(Roguelike::Rng.new SEED))

    player.inventory.add Item.new(Kind::Torch, lit: true)
    player.inventory.add Item.new(Kind::LongSword, enchantment: 1)
    player.inventory.add Item.new(Kind::Arrow, count: 12)
    player.inventory.add Item.new(Kind::HealingPotion)
    player.equipment.put Roguelike::Slot::Melee, 'b'
    player.take_gold 37

    Playing.open game, WINDOW[0], WINDOW[1], title: title, store: store
  end

  # How many swings a spec takes before it gives up waiting for one to land.
  SWINGS = 200

  # A run where the orc killed the character.
  def died : Playing::Run
    run = playing hit_points: 1

    SWINGS.times do
      break if run.game.over?

      run.press "k"
    end

    run
  end

  # A run where the character took the staircase down.
  def won : Playing::Run
    run = playing

    run.press "l", "l", "l", "l", ">"
    run
  end

  describe "the title screen" do
    it "names the seed" do
      run = playing title: true

      expect(run.placard.showing?).to be_true
      expect(run.placard.heading).to eq Placards::NAME
      expect(run.placard.lines.any? &.includes?("seed #{SEED}")).to be_true
    end

    it "names the version it was built from" do
      run = playing title: true

      expect(run.placard.lines).to contain "version #{Roguelike::VERSION}"
    end

    it "plays on p" do
      run = playing title: true

      run.press "p"

      expect(run.placard.showing?).to be_false
      expect(run.finished?).to be_false
    end

    it "asks who is playing once it is answered" do
      run = playing title: true

      run.press "p"

      expect(run.entry.asking?).to be_true
      expect(run.entry.question).to eq Placards::NAME_QUESTION
    end

    it "lists nothing to carry on when the store is empty" do
      run = playing title: true, store: Playing.store

      expect(run.placard.lines.any? &.includes?("Saved characters")).to be_false
    end

    it "lists what is in the store" do
      store = Playing.store
      kept = playing
      kept.game.player.name = "Sparky"
      store.write kept.game

      run = playing title: true, store: store

      expect(run.placard.lines.any? &.includes?("Sparky")).to be_true
    end
  end

  describe "the name question" do
    it "offers a name on the empty line" do
      run = playing title: true

      run.press "p"

      expect(run.entry.field.placeholder).not_to be_empty
      expect(run.entry.text).to be_empty
    end

    # The offer sits where the placeholder goes rather than on the line, so
    # somebody with a name of their own types it without deleting anything
    # first.
    it "takes the offered name on an empty line" do
      run = playing title: true

      run.press "p"
      offered = run.entry.field.placeholder
      run.press "Enter"

      expect(run.game.player.name).to eq offered
      expect(run.entry.asking?).to be_false
    end

    it "offers a different name after a refusal" do
      run = playing title: true

      run.press "p"
      first = run.entry.field.placeholder
      run.type "!!!"
      run.press "Enter"

      expect(run.entry.asking?).to be_true
      expect(run.entry.field.placeholder).not_to eq first
    end

    it "offers a name nothing is saved under" do
      store = Playing.store
      kept = playing
      kept.game.player.name = Roguelike::Names.roll(
        Roguelike::Rng.new(Playing::SEED).derive "name", 0)
      store.write kept.game

      run = playing title: true, store: store
      run.press "p"

      expect(run.entry.field.placeholder).not_to eq kept.game.player.name
    end

    it "names the character with what was typed" do
      run = playing title: true

      run.press "p"
      run.type "Sparky"
      run.press "Enter"

      expect(run.game.player.name).to eq "Sparky"
      expect(run.entry.asking?).to be_false
    end

    it "says who came in" do
      run = playing title: true

      run.press "p"
      run.type "Sparky"
      run.press "Enter"

      expect(run.log).to contain "Sparky enters the dungeon."
    end

    it "writes the character to the store at once" do
      store = Playing.store
      run = playing title: true, store: store

      run.press "p"
      run.type "Sparky"
      run.press "Enter"

      expect(store.holds? "Sparky").to be_true
    end

    # A name is asked for before the first turn, so a person who changes
    # their mind has not lost anything by answering it.
    it "goes back to the title screen on Escape" do
      run = playing title: true

      run.press "p"
      run.press "Escape"

      expect(run.placard.showing?).to be_true
      expect(run.game.player.name).to eq ""
    end

    it "asks again for a name with nothing usable in it" do
      run = playing title: true

      run.press "p"
      run.type "///"
      run.press "Enter"

      expect(run.entry.asking?).to be_true
      expect(run.entry.question).to eq Placards::NAME_UNUSABLE
      expect(run.game.player.name).to eq ""
    end

    # Two names can make one file name. The second one would be written over
    # the first, and nobody types a new name expecting to lose a character.
    it "refuses a name that would write over somebody else" do
      store = Playing.store
      kept = playing
      kept.game.player.name = "Sparky the Bold"
      store.write kept.game

      run = playing title: true, store: store
      run.press "p"
      run.type "Sparky!the!Bold"
      run.press "Enter"

      expect(run.entry.asking?).to be_true
      expect(run.entry.question).to eq Placards.taken("Sparky the Bold")
      expect(run.game.player.name).to eq ""
    end

    it "leaves the file that was in the way where it was" do
      store = Playing.store
      kept = playing
      kept.game.player.name = "Sparky the Bold"
      store.write kept.game

      run = playing title: true, store: store
      run.press "p"
      run.type "Sparky!the!Bold"
      run.press "Enter"

      expect(store.characters.map &.name).to eq ["Sparky the Bold"]
    end

    it "takes the name once the person types another" do
      store = Playing.store
      kept = playing
      kept.game.player.name = "Sparky the Bold"
      store.write kept.game

      run = playing title: true, store: store
      run.press "p"
      run.type "Sparky!the!Bold"
      run.press "Enter"
      run.type "McGee"
      run.press "Enter"

      expect(run.entry.asking?).to be_false
      expect(run.game.player.name).to eq "McGee"
      expect(store.characters.size).to eq 2
    end

    it "carries on a character already in the store" do
      store = Playing.store
      kept = playing
      kept.game.player.name = "Sparky"
      3.times { kept.press "." }
      store.write kept.game

      run = playing title: true, store: store
      run.press "p"
      run.type "Sparky"
      run.press "Enter"

      expect(run.game.turn).to eq 3
      expect(run.game.player.name).to eq "Sparky"
      expect(run.log.last).to contain "Welcome back, Sparky."
    end

    it "plays on Enter" do
      run = playing title: true

      run.press "Enter"

      expect(run.finished?).to be_false
    end

    it "leaves on q" do
      run = playing title: true

      run.press "q"

      expect(run.finished?).to be_true
      expect(run.play.again?).to be_false
    end

    # The box is modal, so a movement key typed at it is not a step.
    it "holds the keyboard while it is up" do
      run = playing title: true
      before = run.at

      run.press "l"

      expect(run.at).to eq before
    end

    it "hands the keyboard back once the name is answered" do
      run = playing title: true

      run.press "p"
      run.type "Sparky"
      run.press "Enter"
      run.press "l"

      expect(run.at).not_to eq({3, 2})
    end
  end

  describe "the screen a death ends with" do
    it "heads it with the death" do
      expect(died.placard.heading).to eq "You died"
    end

    it "names what killed the character" do
      expect(died.placard.lines.first).to eq "Killed by an orc."
      expect(died.game.killer).to eq "orc"
    end

    it "says the turn, the level and the gold" do
      run = died
      written = run.placard.lines

      expect(written.any? &.==("turn #{run.turn}")).to be_true
      expect(written.any? &.includes?("level 1")).to be_true
      expect(written.any? &.==("37 gold")).to be_true
    end

    it "lists what the character was carrying" do
      written = died.placard.lines

      expect(written).to contain "You were carrying:"
      expect(written.any? &.includes?("12 arrows")).to be_true
    end

    # A person who died holding a potion they never drank is told what it
    # was. The run is over and there is nothing left to find out.
    it "names what the character never found out" do
      run = died

      expect(run.game.lore.known? Kind::HealingPotion).to be_false
      expect(run.placard.lines.any? &.includes?("potion of healing")).to be_true
    end

    it "says which slot a readied item is in" do
      expect(died.placard.lines.any? &.includes?("(weapon in hand)")).to be_true
    end

    it "names the seed, so the run can be played again" do
      expect(died.placard.lines.last).to eq "seed #{SEED}"
    end
  end

  describe "the screen a win ends with" do
    it "heads it with the win" do
      run = won

      expect(run.game.outcome).to eq Outcome::Won
      expect(run.placard.heading).to eq "You win"
      expect(run.placard.lines.first).to contain "climbed down"
    end

    it "lists what the character was carrying" do
      expect(won.placard.lines).to contain "You were carrying:"
    end
  end

  describe "the screen leaving ends with" do
    it "heads it with the way the run ended" do
      run = playing

      run.press "<"
      run.press "y"

      expect(run.game.outcome).to eq Outcome::Left
      expect(run.placard.heading).to eq "You left the dungeon"
    end
  end

  describe "asking for another run" do
    it "asks for one on y" do
      run = died

      run.press "y"

      expect(run.finished?).to be_true
      expect(run.play.again?).to be_true
    end

    it "asks for none on n" do
      run = died

      run.press "n"

      expect(run.finished?).to be_true
      expect(run.play.again?).to be_false
    end

    it "asks for none on Escape" do
      run = died

      run.press "Escape"

      expect(run.finished?).to be_true
      expect(run.play.again?).to be_false
    end
  end

  describe "drawn" do
    # The version is compiled in, so the title screen changes with every
    # release. The number is blanked before the comparison, and blanked to
    # its own width, so the fixture holds the layout and not the build.
    def without_version(drawn : String) : String
      blank = "version".ljust Placards.build.size

      drawn.sub Placards.build, blank
    end

    # Each screen written out, so a change to any of the wording shows as a
    # diff of two screens rather than as one failed expectation.
    it "draws the title screen the way it drew it last time" do
      drawn = without_version playing(title: true).text

      expect(drawn).to eq Fixture.expected("screens/title.txt", drawn)
    end

    it "draws the death screen the way it drew it last time" do
      drawn = died.text

      expect(drawn).to eq Fixture.expected("screens/died.txt", drawn)
    end

    it "draws the victory screen the way it drew it last time" do
      drawn = won.text

      expect(drawn).to eq Fixture.expected("screens/won.txt", drawn)
    end
  end
end
