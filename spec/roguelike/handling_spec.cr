require "../spec_helper"

Spectator.describe Roguelike::Handling do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Blessing = Roguelike::Blessing

  # A lit one room floor with the character in the middle and nothing alive
  # on it. Waiting a turn on it does nothing but pass time.
  def bare(seed : UInt64 = Playing::SEED) : Roguelike::Game
    floor = Roguelike::Floor.parse "room", "#####\n#...#\n#.<.#\n#...#\n#####"
    floor.clear_items 2, 2

    Roguelike::Game.new Roguelike::World.new(seed, {"room" => floor}),
      Roguelike::Player.new("room", 2, 2)
  end

  # How much handling an item had when the character worked out its blessing,
  # over *runs* runs. A run that never worked it out is left out.
  #
  # A blessed item rather than a cursed one. Taking hold of a cursed thing
  # tells the character at once, which would leave nothing to measure.
  def reveals(runs : Int32, worn : Bool, turns : Int32 = 4_000) : Array(Int32)
    found = [] of Int32

    runs.times do |index|
      game = bare Playing::SEED + index.to_u64
      item = Item.new Kind::Dagger, blessing: Blessing::Blessed
      letter = game.player.inventory.add item
      raise "no room" unless letter
      game.wield letter if worn

      turns.times do
        break if item.blessing_known?
        game.wait
      end

      found << item.handling if item.blessing_known?
    end

    found
  end

  # How many turns passed before the character worked it out, over *runs*
  # runs.
  def waits(runs : Int32, worn : Bool, turns : Int32 = 4_000) : Array(Int32)
    found = [] of Int32

    runs.times do |index|
      game = bare Playing::SEED + index.to_u64
      item = Item.new Kind::Dagger, blessing: Blessing::Blessed
      letter = game.player.inventory.add item
      raise "no room" unless letter
      game.wield letter if worn

      waited = 0
      turns.times do
        break if item.blessing_known?
        game.wait
        waited += 1
      end

      found << waited if item.blessing_known?
    end

    found
  end

  describe "the numbers" do
    it "is worth more to hold a thing than to carry it" do
      expect(Roguelike::Handling::WORN).to be > Roguelike::Handling::CARRIED
    end

    it "spans from the least to the mean" do
      expect(Roguelike::Handling::SPAN)
        .to eq Roguelike::Handling::MEAN - Roguelike::Handling::LEAST
    end
  end

  describe "noticing a blessing" do
    it "notices nothing below the least handling" do
      game = bare
      item = Item.new Kind::Dagger, blessing: Blessing::Cursed
      game.player.inventory.add item

      (Roguelike::Handling::LEAST - 1).times { game.wait }

      expect(item.handling).to eq Roguelike::Handling::LEAST - 1
      expect(item.blessing_known?).to be_false
    end

    it "adds one for a turn carried" do
      game = bare
      item = Item.new Kind::Dagger
      game.player.inventory.add item
      game.wait

      expect(item.handling).to eq Roguelike::Handling::CARRIED
    end

    it "adds more for a turn in the hand" do
      game = bare
      item = Item.new Kind::Dagger
      letter = game.player.inventory.add item
      raise "no room" unless letter
      game.wield letter

      before = item.handling
      game.wait

      expect(item.handling - before).to eq Roguelike::Handling::WORN
    end

    it "stops counting once the character knows" do
      game = bare
      item = Item.new Kind::Dagger, blessing_known: true
      game.player.inventory.add item
      20.times { game.wait }

      expect(item.handling).to eq 0
    end

    # The roll past the least is geometric, so the mean rather than any one
    # run is what the number says.
    it "notices at about the mean handling" do
      found = reveals 120, worn: false
      mean = found.sum / found.size.to_f

      expect(found.size).to eq 120
      expect(mean).to be > Roguelike::Handling::MEAN - 25
      expect(mean).to be < Roguelike::Handling::MEAN + 25
    end

    it "notices a held thing in about a third of the turns" do
      carried = reveals 60, worn: false
      held = reveals 60, worn: true

      expect(held.size).to eq 60
      expect(carried.size).to eq 60

      # The same handling either way. What differs is how long it takes to
      # get there, which is a third of the turns.
      expect(held.sum / held.size.to_f)
        .to be > carried.sum / carried.size.to_f - 35
      expect(held.sum / held.size.to_f)
        .to be < carried.sum / carried.size.to_f + 35
    end

    it "takes about a third as many turns to notice a held thing" do
      carried = waits 60, worn: false
      held = waits 60, worn: true

      ratio = (held.sum / held.size.to_f) / (carried.sum / carried.size.to_f)
      expect(ratio).to be > 0.2
      expect(ratio).to be < 0.5
    end

    describe "what it says" do
      # A stack of three takes "are" and a single spike takes "is".
      it "agrees the verb with the count" do
        lore = Roguelike::Lore.new
        one = Item.new Kind::Spike, blessing: Blessing::Cursed,
          blessing_known: true
        several = Item.new Kind::Spike, count: 3, blessing: Blessing::Cursed,
          blessing_known: true

        expect(Roguelike::Game.worked_out lore, one)
          .to eq "You realize that an iron spike is cursed!"
        expect(Roguelike::Game.worked_out lore, several)
          .to eq "You realize that 3 iron spikes are cursed!"
      end

      it "leaves the blessing word out of the name" do
        lore = Roguelike::Lore.new
        cursed = Item.new Kind::Spike, blessing: Blessing::Cursed,
          blessing_known: true
        blessed = Item.new Kind::Spike, count: 3, blessing: Blessing::Blessed,
          blessing_known: true

        expect(Roguelike::Game.worked_out lore, cursed)
          .to eq "You realize that an iron spike is cursed!"
        expect(Roguelike::Game.worked_out lore, blessed)
          .to eq "You realize that 3 iron spikes are blessed!"
      end

      it "reads an uncountable kind as one thing" do
        lore = Roguelike::Lore.new
        armor = Item.new Kind::LeatherArmor, blessing: Blessing::Cursed,
          blessing_known: true

        expect(Roguelike::Game.worked_out lore, armor)
          .to eq "You realize that leather armor is cursed!"
      end

      # Almost everything a character carries is uncursed, and a line for
      # each of them would fill the log and stop every walk.
      it "says nothing about an uncursed item" do
        lore = Roguelike::Lore.new
        one = Item.new Kind::Dagger, blessing_known: true
        several = Item.new Kind::Arrow, count: 3, blessing_known: true

        expect(Roguelike::Game.worked_out lore, one).to be_nil
        expect(Roguelike::Game.worked_out lore, several).to be_nil
      end
    end

    it "says what it worked out" do
      game = bare
      item = Item.new Kind::Dagger, blessing: Blessing::Cursed
      game.player.inventory.add item
      2_000.times { break if item.blessing_known?; game.wait }

      expect(item.blessing_known?).to be_true
      expect(game.log.lines.any? &.includes?("cursed")).to be_true
    end

    # The character works it out and the pack shows it. Nothing is written
    # to the log.
    it "says nothing when it works out that something is uncursed" do
      game = bare
      item = Item.new Kind::Dagger
      game.player.inventory.add item
      said = game.log.size
      2_000.times { break if item.blessing_known?; game.wait }

      expect(item.blessing_known?).to be_true
      expect(game.log.size).to eq said
    end

    it "rolls the same from the same seed" do
      first = bare 77_u64
      again = bare 77_u64

      [first, again].each do |game|
        game.player.inventory.add Item.new(Kind::Dagger, blessing: Blessing::Cursed)
      end

      400.times { first.wait; again.wait }

      expect(again.player.inventory['a'].try &.handling)
        .to eq first.player.inventory['a'].try &.handling
      expect(again.player.inventory['a'].try &.blessing_known?)
        .to eq first.player.inventory['a'].try &.blessing_known?
    end
  end

  describe "the split" do
    it "moves what it noticed to a letter of its own" do
      game = bare
      plain = Item.new Kind::Arrow, count: 12
      cursed = Item.new Kind::Arrow, count: 3, blessing: Blessing::Cursed
      game.player.inventory.add plain
      game.player.inventory.add cursed

      expect(game.player.inventory.size).to eq 1
      expect(game.player.inventory.count 'a').to eq 15

      2_000.times { break if cursed.blessing_known?; game.wait }

      expect(cursed.blessing_known?).to be_true
      expect(game.player.inventory.size).to eq 2
    end

    # Every letter is taken, so there is nowhere for the split to go. What
    # the character has just worked out keeps the letter and the rest goes
    # on the floor.
    it "puts the rest down when there is no letter left" do
      game = bare
      plain = Item.new Kind::Arrow, count: 12
      cursed = Item.new Kind::Arrow, count: 3, blessing: Blessing::Cursed
      game.player.inventory.add plain
      game.player.inventory.add cursed

      Roguelike::Inventory::LETTERS.each do |letter|
        next if letter == 'a'
        game.player.inventory.slots[letter] =
          Roguelike::Inventory::Stack.of Item.new(Kind::Dagger)
      end

      2_000.times { break if cursed.blessing_known?; game.wait }

      expect(cursed.blessing_known?).to be_true
      expect(game.player.inventory.all('a')).to eq [cursed]
      expect(game.here.map &.kind).to eq [Kind::Arrow]
      expect(game.here.first.count).to eq 12
    end
  end
end
