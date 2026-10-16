require "../../spec_helper"

Spectator.describe Roguelike::Ui::InfoPanel do
  alias InfoPanel = Roguelike::Ui::InfoPanel
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Palette = Roguelike::Ui::Palette

  # A file in a directory of its own that the specs remove when they end.
  def kept : Path
    Path[File.tempname "roguelike-sections", nil] / InfoPanel::FILE
  end

  # Three sections in a panel, all open.
  def panel : InfoPanel
    InfoPanel.new %w[Scores Pack Seen].map { |title| InfoPanel.section title }
  end

  # The screen, then a blank row, then one row of marks for each row of the
  # screen. `H` is a cell on the header ground.
  def marked(run : Playing::Run) : String
    text = run.text
    marks = (0...run.buffer.height).map do |row|
      String.build do |line|
        run.buffer.width.times do |column|
          found = run.buffer.hit column, row
          style = found ? run.buffer.styles[found.cell.style] : TermBuf::Style::DEFAULT
          line << (style.background == Palette::HEADER_GROUND ? 'H' : '.')
        end
      end
    end

    "#{text}\n\n#{marks.join '\n'}"
  end

  # A run carrying one of every kind the game makes, with a sword and a cap
  # readied, on a screen of *columns* by *rows*.
  def loaded(columns : Int32, rows : Int32) : Playing::Run
    game = Roguelike::Game.start(Roguelike::Rng.new(Playing::SEED))
    Kind.values.each_with_index do |kind, index|
      next if kind.gold?

      game.player.inventory.add Item.new(kind, enchantment: index % 3)
    end
    game.wield letter(game, Kind::LongSword)
    game.wear letter(game, Kind::Cap)

    Playing.open game, columns, rows
  end

  # The letter the first *kind* in the pack is carried under.
  def letter(game : Roguelike::Game, kind : Kind) : Char
    game.player.inventory.entries.find!(&.[1].kind.==(kind))[0]
  end

  describe "the remembered state" do
    it "starts with the pack closed when there is no file" do
      found = panel
      found.path = kept

      expect(found.sections.map &.expanded?).to eq [true, false, true]
      expect(File.exists?(found.path || raise "no path")).to be_false
    end

    it "starts with the pack closed when the file cannot be read" do
      path = kept
      Dir.mkdir_p path.parent
      File.write path, "not json"
      found = panel
      found.path = path

      expect(found.sections.map &.expanded?).to eq [true, false, true]
    ensure
      FileUtils.rm_rf path.parent.to_s if path
    end

    it "writes the state when a section toggles" do
      path = kept
      found = panel
      found.path = path
      found.sections[1].toggle

      expect(File.read path).to eq %({"expanded":{"scores":true,"pack":true,"seen":true}})
    ensure
      FileUtils.rm_rf path.parent.to_s if path
    end

    it "reads it back into a new panel" do
      path = kept
      first = panel
      first.path = path
      first.sections[0].toggle
      first.sections[1].toggle

      second = panel
      second.path = path

      expect(second.sections.map &.expanded?).to eq [false, true, true]
    ensure
      FileUtils.rm_rf path.parent.to_s if path
    end

    it "keeps the state in the run's state directory" do
      store = Playing.store
      run = Playing.open store: store
      run.play.character.toggle_pack

      expect(run.play.info_panel.path).to eq store.root / InfoPanel::FILE
      expect(File.exists? store.root / InfoPanel::FILE).to be_true

      again = Playing.open store: store
      expect(again.play.character.showing_pack?).to be_true
    end

    it "keeps the state when the focus moves" do
      run = Playing.open
      run.play.character.toggle_pack
      run.press "Tab"
      run.press "Tab"

      expect(run.play.character.showing_pack?).to be_true
    end
  end

  describe "the panel" do
    it "stacks the sections in order" do
      run = Playing.open

      expect(run.play.info_panel.sections.map &.title)
        .to eq %w[Scores Equipment Pack Here Seen Look]
    end

    it "toggles a section on a click on its header" do
      run = Playing.open
      run.render
      header = run.play.character.worn_heading.rect

      run.click header.x + 2, header.y

      expect(run.play.character.worn.expanded?).to be_true
    end

    it "keeps the click off the map" do
      run = Playing.open
      run.render
      before = run.examiner.spot
      header = run.play.nearby.seen_section.header.rect

      run.click header.x + 2, header.y

      expect(run.examiner.spot).to eq before
    end

    it "names what the Look section last looked at on its shut header" do
      run = Playing.open
      run.play.examine.section.toggle
      expect(run.play.examine.section.summary).to be_empty

      start = run.at
      spot = run.map.screen_of(start[0], start[1]) || raise "the character is off the screen"
      run.hover *spot

      expect(run.play.examine.section.summary).to eq run.play.examine.what.text
    end
  end

  describe "drawn" do
    it "draws what it drew last time with every section open at 80 by 24" do
      run = Playing.open
      run.play.character.worn.toggle
      run.play.character.packed.toggle
      drawn = marked run

      expect(drawn).to eq Fixture.expected("screen/info-all-open.txt", drawn)
    end

    it "draws what it drew last time with a full pack at 200 by 50" do
      run = loaded(200, 50)
      run.play.character.worn.toggle
      run.play.character.packed.toggle
      drawn = marked run

      expect(drawn).to eq Fixture.expected("screen/info-full-pack.txt", drawn)
    end
  end
end
