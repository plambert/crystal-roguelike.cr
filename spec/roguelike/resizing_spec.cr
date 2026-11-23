require "../spec_helper"

Spectator.describe "an oil of resizing" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Lore = Roguelike::Lore
  alias Size = Roguelike::Size
  alias Action = Roguelike::Action

  # A lit room with the character in the middle and nothing on the floor.
  def bare : Roguelike::Game
    floor = Roguelike::Floor.parse "room", "#####\n#...#\n#.<.#\n#...#\n#####"
    floor.clear_items 2, 2
    floor.ambient = 1

    Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}),
      Roguelike::Player.new("room", 2, 2)
  end

  # Puts *item* in the pack and answers its letter.
  def carrying(game : Roguelike::Game, item : Item) : Char
    letter = game.player.inventory.add item
    raise "no room" unless letter
    letter
  end

  def oil(game : Roguelike::Game) : Char
    carrying game, Item.new(Kind::ResizingOil)
  end

  it "cuts small leather armor for the character" do
    game = bare
    armor = carrying game, Item.new(Kind::LeatherArmor, size: Size::Small)

    expect(game.quaff oil(game), armor).to be_true

    expect(game.player.inventory[armor].try &.size).to eq Size::Medium
    expect(game.log.last?.to_s).to eq "Small leather armor grows to fit you."
  end

  it "cuts a large cap down" do
    game = bare
    cap = carrying game, Item.new(Kind::Cap, size: Size::Large)

    game.quaff oil(game), cap

    expect(game.player.inventory[cap].try &.size).to eq Size::Medium
    expect(game.log.last?.to_s).to eq "A large cap shrinks to fit you."
  end

  it "takes the penalty off a small shield" do
    game = bare
    shield = carrying game, Item.new(Kind::Shield, size: Size::Small)

    game.quaff oil(game), shield

    expect(game.player.inventory[shield].try &.misfit(Size::Medium)).to eq 0
  end

  it "runs off metal armor and is used up" do
    game = bare
    mail = carrying game, Item.new(Kind::ChainMail, size: Size::Small)
    letter = oil game

    game.quaff letter, mail

    expect(game.player.inventory[mail].try &.size).to eq Size::Small
    expect(game.player.inventory[letter]).to be_nil
    expect(game.log.last?.to_s).to eq "The oil runs off the metal of small chain mail."
  end

  it "does nothing to what is not armor" do
    game = bare
    dagger = carrying game, Item.new(Kind::Dagger)

    game.quaff oil(game), dagger

    expect(game.log.last?.to_s).to eq "Nothing about a dagger changes."
  end

  it "says it was rubbed on rather than drunk" do
    game = bare
    cap = carrying game, Item.new(Kind::Cap, size: Size::Small)
    letter = oil game

    game.quaff letter, cap

    expect(game.log.lines).to contain "You rub an oil of resizing on a small cap."
  end

  it "is offered once for each other carried item" do
    game = bare
    cap = carrying game, Item.new(Kind::Cap, size: Size::Small)
    letter = oil game
    id = game.player.inventory[letter].try &.id
    cap_id = game.player.inventory[cap].try &.id

    quaffs = game.legal.select(Action::Quaff).select { |action| action.item == id }
    expect(quaffs.map &.choice).to contain cap_id
    expect(quaffs.none? { |action| action.choice.nil? }).to be_true
  end

  it "is called a vial of oil until it is known" do
    lore = Lore.roll Roguelike::Rng.new(5_u64)
    look = lore.appearance(Kind::ResizingOil) || raise "no look"

    expect(Lore::OIL_LOOKS).to contain look
    expect(lore.name Item.new(Kind::ResizingOil)).to eq "a vial of #{look} oil"
    expect(lore.name Item.new(Kind::ResizingOil, count: 2)).to eq "2 vials of #{look} oil"
  end

  it "leaves every other look where it was" do
    lore = Lore.roll Roguelike::Rng.new(5_u64)
    stream = Roguelike::Rng.new(5_u64).derive Lore::DOMAIN
    potions = Lore::POTION_LOOKS.shuffle stream

    Roguelike::ItemKind.of_class(Roguelike::ItemClass::Potion).reject(&.oil?).each_with_index do |kind, index|
      expect(lore.appearance kind).to eq potions[index]
    end
  end

  it "gets a look in a save from before it existed" do
    lore = Lore.roll Roguelike::Rng.new(5_u64)
    json = JSON.parse(lore.to_json).as_h
    looks = json["appearances"].as_h.reject { |key, _look| key == Kind::ResizingOil.to_json_object_key }
    json["appearances"] = JSON::Any.new looks

    loaded = Lore.from_json json.to_json

    expect(loaded.appearance Kind::ResizingOil).to eq "orange"
  end
end
