require "../../spec_helper"

Spectator.describe "how a flame is drawn" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias LightKind = Roguelike::LightKind
  alias Ui = Roguelike::Ui

  # A long dark hall. The character stands at one end with a lit torch, so
  # the pool has an edge inside the room.
  HALL = [
    "####################",
    "#..................#",
    "#.<................#",
    "#..................#",
    "####################",
  ]

  def burning : Playing::Run
    floor = Roguelike::Floor.parse "hall", HALL
    player = Roguelike::Player.new "hall", *Roguelike::Game.entrance(floor)
    player.inventory.add Playing.torch

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}), player), 40, 16
  end

  def drawn_style(run : Playing::Run, x : Int32, y : Int32) : TermBuf::Style
    found = run.buffer.hit x, y
    raise "nothing is drawn at #{x},#{y}" unless found

    run.buffer.styles[found.cell.style]
  end

  describe "the tint" do
    # Firelight reads as warm and a magically lit room as cold. Stone under a
    # torch is still stone.
    it "warms a square a flame lights" do
      plain = Ui::Palette.shaded Ui::Palette[Roguelike::Terrain::StoneFloor], 3
      warm = Ui::Palette.shaded Ui::Palette[Roguelike::Terrain::StoneFloor], 3,
        LightKind::Flame

      expect(warm.style.foreground.red).to be > plain.style.foreground.red
      expect(warm.style.foreground.blue).to be < plain.style.foreground.blue
    end

    it "cools a square a magic light reaches" do
      plain = Ui::Palette.shaded Ui::Palette[Roguelike::Terrain::StoneFloor], 3
      cold = Ui::Palette.shaded Ui::Palette[Roguelike::Terrain::StoneFloor], 3,
        LightKind::Glimmer

      expect(cold.style.foreground.blue).to be > plain.style.foreground.blue
    end

    # What lights a square now says nothing about what it looked like when it
    # was last seen.
    it "leaves a remembered square alone" do
      base = Ui::Palette[Roguelike::Terrain::StoneFloor]
      plain = Ui::Palette.shaded base, Ui::Palette::REMEMBERED
      lit = Ui::Palette.shaded base, Ui::Palette::REMEMBERED, LightKind::Flame

      expect(lit).to eq plain
    end

    it "leaves stone looking like stone" do
      base = Ui::Palette[Roguelike::Terrain::StoneFloor].style.foreground
      warm = Ui::Palette.shaded(Ui::Palette[Roguelike::Terrain::StoneFloor], 4,
        LightKind::Flame).style.foreground

      expect((warm.red - base.red).abs).to be < 40
      expect((warm.green - base.green).abs).to be < 40
    end
  end

  describe "what the lighting says is on a square" do
    it "calls a torch pool firelight" do
      run = burning

      expect(run.game.sight.light_kind(3, 2)).to eq LightKind::Flame
    end

    it "calls a floor lit throughout a glimmer" do
      floor = Playing.daylight Roguelike::Floor.parse("room", HALL)
      game = Roguelike::Game.new Roguelike::World.new(1_u64, {"room" => floor}),
        Roguelike::Player.new("room", 2, 2)

      expect(game.sight.light_kind(6, 2)).to eq LightKind::Glimmer
    end

    it "says nothing about a square with no light" do
      run = burning

      expect(run.game.sight.light_kind(18, 2)).to be_nil
    end

    # A torch beside a lit room leaves the squares nearest it reading as
    # firelight and the rest as the room's.
    it "takes the stronger of two sources" do
      floor = Roguelike::Floor.parse "room", ["#########", "#*******#", "#########"]
      lighting = Roguelike::Lighting.over floor,
        [Roguelike::LightSource.new(1, 1, 6)]

      expect(lighting.kind_at 1, 1).to eq LightKind::Flame
      expect(lighting.kind_at 7, 1).to eq LightKind::Glimmer
    end
  end

  describe "a tick of the flame" do
    it "changes what some square is drawn in" do
      run = burning
      before = (0...20).map { |column| drawn_style(run, column, 2).foreground }

      20.times do
        run.play.waver
        run.render
      end

      after = (0...20).map { |column| drawn_style(run, column, 2).foreground }
      expect(after).not_to eq before
    end

    # Every square a flame lights moves together, so a tick either changes
    # the whole pool or none of it.
    it "moves the whole pool or none of it" do
      run = burning
      still = (0...20).map { |column| drawn_style(run, column, 2).foreground }

      moved = (0...40).map do
        run.play.waver
        run.render
        (0...20).map { |column| drawn_style(run, column, 2).foreground }
      end

      # Every frame is either the still one or one shade off it throughout.
      whole = moved.count { |frame| frame == still }
      expect(whole).to be > 0
      expect(whole).to be < 40
    end

    # It shifts which shade a square draws at and no more.
    it "leaves what can be seen alone" do
      run = burning
      before = run.game.sight.size

      20.times { run.play.waver; run.render }

      expect(run.game.sight.size).to eq before
    end

    it "takes no turn" do
      run = burning

      20.times { run.play.waver; run.render }

      expect(run.turn).to eq 0
    end

    it "remembers nothing new" do
      run = burning
      before = run.game.knowledge.size

      20.times { run.play.waver; run.render }
      run.play.refresh
      run.render

      expect(run.game.knowledge.size).to eq before
    end

    it "leaves the glyphs alone" do
      run = burning
      before = run.rows

      20.times { run.play.waver; run.render }

      expect(run.rows).to eq before
    end
  end

  # A blend computing a colour per cell interns a style per cell. The ramps
  # cache, so the table settles even with the flame moving.
  describe "the style table under a flame" do
    it "stops growing once the flame has been through its shades" do
      run = burning

      200.times { run.play.waver; run.render }
      settled = run.buffer.styles.size

      400.times { run.play.waver; run.render }

      expect(run.buffer.styles.size).to eq settled
    end

    it "settles at a size a person could count" do
      run = burning

      200.times { run.play.waver; run.render }

      expect(run.buffer.styles.size).to be < 80
    end
  end

  describe "a pane with no flicker" do
    it "draws the same map every time" do
      run = burning
      run.map.flicker = nil
      run.render
      before = (0...20).map { |column| drawn_style(run, column, 2).foreground }

      20.times { run.play.waver; run.render }

      expect((0...20).map { |column| drawn_style(run, column, 2).foreground }).to eq before
    end
  end
end
