require "../../spec_helper"

Spectator.describe Roguelike::Ui::CharacterPane do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Naming = Roguelike::Ui::Naming
  alias Pane = Roguelike::Ui::CharacterPane
  alias Slot = Roguelike::Slot

  # A run on one open room, drawn in a window of *rows*.
  def playing(rows : Int32 = 40, carrying : Array(Item) = [] of Item,
              name : String = "") : Playing::Run
    game = Playing.field 30, 16
    game.player.name = name
    carrying.each { |item| game.player.inventory.add item }

    Playing.open game, 80, rows
  end

  # Which row of the pane holds *slot*.
  def slot_row(run : Playing::Run, slot : Slot) : Roguelike::Ui::Line
    run.play.character.slot_row slot
  end

  describe "what it writes" do
    it "heads it with the name and the level" do
      run = playing name: "Sparky"

      expect(run.play.character.who.text).to eq "SparkyLv 1"
    end

    # A run holds no name until the title screen has been answered, and a
    # spec builds a character that never goes near one.
    it "heads a character nobody has named with a dash" do
      run = playing

      expect(run.play.character.who.text).to eq "#{Pane::NOBODY}Lv 1"
    end

    it "draws the level against the right edge" do
      run = playing name: "Sparky"
      row = run.row run.play.character.who.rect.y

      expect(row.rstrip).to end_with "Lv 1"
      expect(row).to contain "Sparky"
    end

    # The level is what a person reads every turn. A long name gives way to
    # it rather than pushing it off the row.
    it "cuts a name too long for the row" do
      run = playing name: "Bartholomew the Unreasonably Long"
      row = run.row run.play.character.who.rect.y

      expect(row.rstrip).to end_with "Lv 1"
      expect(row).to contain Roguelike::Ui::Line::ELLIPSIS
    end

    it "writes the armour class, the gold and the turn" do
      run = playing
      run.game.player.take_gold 40
      run.play.refresh

      written = run.play.character.numbers.text
      expect(written).to contain "ac0"
      expect(written).to contain "au40"
      expect(written).to contain "t0"
    end

    it "writes the five scores under their names" do
      run = playing

      expect(run.play.character.score_names.text).to eq "StDxCnInSl"
      expect(run.play.character.scores.text).to eq "10" * 5
    end

    it "fills the hit point bar from the character" do
      run = playing
      player = run.game.player

      expect(run.play.character.health.value).to eq player.hit_points
      expect(run.play.character.health.most).to eq player.max_hit_points
    end

    # The bar is the part of this level that is done, so a full bar always
    # means the next level. The reading is the whole count either way.
    it "fills the experience bar with the part of the level that is done" do
      run = playing
      run.game.player.gain 30
      run.play.refresh

      learning = run.play.character.learning
      expect(learning.value).to eq 30 - Roguelike::Advancement.threshold(2)
      expect(learning.reading).to eq "30/40"
    end

    it "shows no magic bar until there is magic" do
      expect(playing.play.character.magic.hidden?).to be_true
    end
  end

  describe "the equipment rows" do
    it "writes a row for every slot, in the order it lists them" do
      run = playing

      Slot.listed.each_with_index do |slot, index|
        expect(run.play.character.slots[index].text).to start_with slot.short
      end
    end

    # A person learns which row the weapon is on. A row that came and went
    # would make them read the labels every time.
    it "writes an empty slot rather than leaving the row out" do
      run = playing

      expect(slot_row(run, Slot::Melee).text).to eq "wpn#{Pane::NOTHING}"
    end

    it "writes what is in a slot in the colour the map draws it in" do
      run = playing carrying: [Item.new(Kind::LongSword)]
      run.game.wield 'a'
      run.play.refresh

      expect(slot_row(run, Slot::Melee).text).to eq "wpnlong swd"
    end
  end

  describe "the pack" do
    it "is shut to begin with" do
      expect(playing.play.character.showing_pack?).to be_false
    end

    it "opens and shuts on the triangle" do
      pane = playing.play.character

      pane.toggle_pack
      expect(pane.showing_pack?).to be_true
      expect(pane.pack_heading.text).to start_with Pane::OPEN.to_s

      pane.toggle_pack
      expect(pane.showing_pack?).to be_false
      expect(pane.pack_heading.text).to start_with Pane::SHUT.to_s
    end

    it "writes a row per entry, by its letter" do
      run = playing carrying: [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 14)]
      run.play.character.toggle_pack
      run.play.refresh

      expect(run.play.character.pack[0].text).to eq "a)bow"
      expect(run.play.character.pack[1].text).to eq "b)14 arrow"
    end

    it "says how many entries did not fit" do
      many = (0...(Pane::MOST_PACK + 3)).map do |plus|
        Item.new Kind::Dagger, enchantment: plus
      end
      run = playing carrying: many
      run.play.character.toggle_pack
      run.play.refresh

      expect(run.play.character.pack[Pane::MOST_PACK].text).to eq "3 more"
    end
  end

  describe "#fit" do
    # The level and the bars are what a person reads every turn. Everything
    # else gives way before they do.
    it "keeps the level and the bars in a window with almost no room" do
      pane = playing.play.character
      pane.fit Pane::LEAST

      expect(pane.vitals.hidden?).to be_false
      expect(pane.worn.hidden?).to be_true
    end

    it "shuts an open pack before it drops anything else" do
      run = playing carrying: [Item.new(Kind::Bow)]
      pane = run.play.character
      pane.toggle_pack
      run.play.refresh

      pane.fit pane.height - 1

      expect(pane.scoring.hidden?).to be_false
      expect(pane.worn.hidden?).to be_false
    end

    it "gives everything back when the window grows again" do
      pane = playing.play.character
      pane.fit Pane::LEAST
      pane.fit 100

      expect(pane.scoring.hidden?).to be_false
      expect(pane.worn.hidden?).to be_false
      expect(pane.packed.hidden?).to be_false
    end

    it "never takes more rows than it was given" do
      pane = playing.play.character

      (Pane::LEAST..40).each do |room|
        pane.fit room

        expect(pane.height).to be <= room
      end
    end
  end

  describe "on the screen" do
    it "leaves the three readouts room at the shortest terminal there is" do
      run = playing rows: Roguelike::Ui::Screen::MINIMUM_ROWS
      drawn = run.text

      expect(drawn).to contain "Here"
      expect(drawn).to contain "Seen"
      expect(drawn).to contain "Look"
    end

    it "shows everything but the pack at a tall terminal" do
      drawn = playing(rows: 50).text

      expect(drawn).to contain "Lv 1"
      expect(drawn).to contain "Worn/Wielded"
      expect(drawn).to contain "Pack"
      expect(drawn).to contain "Here"
    end
  end
end
