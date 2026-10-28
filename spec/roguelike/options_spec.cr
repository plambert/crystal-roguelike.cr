require "../spec_helper"

Spectator.describe Roguelike::Options do
  alias Options = Roguelike::Options
  alias Tester = Roguelike::Tester
  alias Palette = Roguelike::Ui::Palette

  # A state directory of its own. The specs never touch the real one.
  let(root) do
    Path[File.tempname "roguelike-options", nil].tap do |made|
      Dir.mkdir_p made
      at_exit { FileUtils.rm_rf made.to_s }
    end
  end

  # Writes *text* as the options file under *where*.
  def filed(where : Path, text : String) : Nil
    File.write Options.path(where), text
  end

  # What the file under *where* holds, as JSON.
  def written(where : Path) : JSON::Any
    JSON.parse File.read(Options.path where)
  end

  it "is nil unless the interactive game sets it" do
    expect(Options.current).to be_nil
  end

  describe "the defaults" do
    it "has every option at its default" do
      options = Options.new

      expect(options.motion?).to be_true
      expect(options.flicker?).to be_true
      expect(options.bar_color).to eq Options::BarColor::Gradient
      expect(options.mouse?).to be_true
      expect(options.update_check?).to be_true
      expect(options.autosubmit?).to eq Roguelike::TEST_BUILD
    end
  end

  describe ".read" do
    it "answers the defaults when there is no file" do
      expect(Options.read(root).to_json).to eq Options.new.to_json
    end

    it "answers the defaults when the file does not parse" do
      filed root, "{ not json"

      expect(Options.read(root).to_json).to eq Options.new.to_json
    end

    it "keeps the default of a key the file lacks" do
      filed root, %({"motion": false})
      options = Options.read root

      expect(options.motion?).to be_false
      expect(options.flicker?).to be_true
      expect(options.bar_color).to eq Options::BarColor::Gradient
    end

    it "ignores a key it does not know" do
      filed root, %({"motion": false, "gone": 3})

      expect(Options.read(root).motion?).to be_false
    end
  end

  describe "#write" do
    it "reads back what it wrote" do
      options = Options.new
      options.motion = false
      options.bar_color = Options::BarColor::Bands
      options.mouse = false
      options.write root

      back = Options.read root
      expect(back.motion?).to be_false
      expect(back.bar_color).to eq Options::BarColor::Bands
      expect(back.mouse?).to be_false
      expect(back.flicker?).to be_true
    end

    it "writes every key" do
      Options.new.write root

      expect(written(root).as_h.keys).to contain_exactly(
        "motion", "flicker", "bar_color", "mouse", "control_scheme",
        "update_check", "autosubmit", "explore")
    end
  end

  describe "flag precedence" do
    it "uses the file where no flag was typed" do
      filed root, %({"motion": false, "update_check": false})
      options = Options.arrange root

      expect(options.motion?).to be_false
      expect(options.update_check?).to be_false
      expect(options.overridden?("motion")).to be_false
    end

    it "lets a typed flag win for the run" do
      filed root, %({"motion": true, "flicker": false})
      options = Options.arrange root, motion: false, flicker: true

      expect(options.motion?).to be_false
      expect(options.flicker?).to be_true
      expect(options.overridden?("motion")).to be_true
    end

    it "does not write a typed flag to the file" do
      filed root, %({"motion": true})
      Options.arrange root, motion: false

      expect(written(root)["motion"].as_bool).to be_true
    end

    it "keeps the file's value of a flagged key when the options are written" do
      filed root, %({"motion": true})
      options = Options.arrange root, motion: false
      options.mouse = false
      options.write root

      expect(written(root)["motion"].as_bool).to be_true
      expect(written(root)["mouse"].as_bool).to be_false
    end

    it "writes a flagged key once it is adopted" do
      filed root, %({"motion": true})
      options = Options.arrange root, motion: false
      options.adopt "motion"
      options.write root

      expect(written(root)["motion"].as_bool).to be_false
    end

    it "creates no file when there is none" do
      Options.arrange root, motion: false

      expect(File.exists? Options.path(root)).to be_false
    end

    it "tells a typed flag from a default on the command line" do
      expect(Roguelike::Cli.parse(%w[]).flag_given?(:motion)).to be_false
      expect(Roguelike::Cli.parse(%w[--no-motion]).flag_given?(:motion)).to be_true
      expect(Roguelike::Cli.parse(%w[--motion]).flag_given?(:motion)).to be_true
      expect(Roguelike::Cli.parse(%w[--no-update-check]).flag_given?(:update_check)).to be_true
      expect(Roguelike::Cli.parse(%w[--no-motion]).flag_given?(:flicker)).to be_false
    end
  end

  describe "SETTINGS" do
    it "names each option once" do
      keys = Options::SETTINGS.map(&.key)

      expect(keys.uniq).to eq keys
    end

    it "names a property for every setting except the tester's name" do
      keys = Options::SETTINGS.map(&.key) - ["name"]
      plain = keys.reject(&.starts_with? Options::EXPLORE) + ["explore"]

      expect(plain).to contain_exactly(*JSON.parse(Options.new.to_json).as_h.keys)
    end

    it "names every explore setting once" do
      keys = Options::SETTINGS.map(&.key).select(&.starts_with? Options::EXPLORE)

      expect(keys.map(&.lchop Options::EXPLORE)).to contain_exactly(*Roguelike::Explore::Settings.keys)
    end

    it "offers a choice for every bar color" do
      bar = Options::SETTINGS.find!(&.key.== "bar_color")
      values = Options::BarColor.values.map(&.to_s.underscore)

      expect(bar.choices.map(&.[0])).to eq values
    end
  end

  describe "the tester's name" do
    after { Tester.current = nil }

    it "is anonymous when there is no tester file" do
      expect(Options.name(root)).to eq Tester::ANONYMOUS
    end

    it "writes through the tester file and keeps the id" do
      held = Tester.named "Ada"
      held.write root

      renamed = Options.rename root, "Grace"

      expect(renamed.id).to eq held.id
      expect(Tester.read(root).try(&.name)).to eq "Grace"
      expect(Options.name(root)).to eq "Grace"
      expect(Tester.current).to eq renamed
    end
  end

  describe "#apply" do
    it "pushes motion" do
      was = Roguelike::Ui::Motion.on?

      begin
        options = Options.new
        options.apply
        expect(Roguelike::Ui::Motion.on?).to be_true

        options.motion = false
        options.apply
        expect(Roguelike::Ui::Motion.on?).to be_false
      ensure
        Roguelike::Ui::Motion.on = was
      end
    end
  end

  describe "bar color" do
    it "mixes between levels as a gradient" do
      expect(Palette.meter(Palette.health, 90)).not_to eq Palette.green
      expect(Palette.meter(Palette.health, 90)).not_to eq Palette.light_green
    end

    it "takes the nearer level as bands" do
      expect(Palette.meter(Palette.health, 90, banded: true)).to eq Palette.green
      expect(Palette.meter(Palette.health, 89, banded: true)).to eq Palette.light_green
      expect(Palette.meter(Palette.health, 10, banded: true)).to eq Palette.red
    end
  end
end
