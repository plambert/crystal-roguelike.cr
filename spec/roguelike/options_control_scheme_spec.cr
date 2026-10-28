require "../spec_helper"

Spectator.describe Roguelike::Options do
  alias Options = Roguelike::Options
  alias ControlScheme = Roguelike::Options::ControlScheme

  let(root) do
    Path[File.tempname "roguelike-control-scheme", nil].tap do |made|
      Dir.mkdir_p made
      at_exit { FileUtils.rm_rf made.to_s }
    end
  end

  def file_options(where : Path, contents : String) : Nil
    File.write Options.path(where), contents
  end

  def saved_options(where : Path) : JSON::Any
    JSON.parse File.read(Options.path where)
  end

  describe "control scheme migration" do
    it "treats a missing choice as unchosen and resolves it to Traditional" do
      file_options root, %({"motion": false, "mouse": false})
      options = Options.read root

      expect(options.control_scheme).to be_nil
      expect(options.control_scheme_chosen?).to be_false
      expect(options.effective_control_scheme).to eq ControlScheme::Traditional
      expect(options.motion?).to be_false
      expect(options.mouse?).to be_false
    end

    it "reads both recognized saved values" do
      {"traditional" => ControlScheme::Traditional, "modern" => ControlScheme::Modern}
        .each do |name, scheme|
          file_options root, %({"control_scheme": "#{name}"})
          options = Options.read root

          expect(options.control_scheme).to eq scheme
          expect(options.control_scheme_chosen?).to be_true
          expect(options.effective_control_scheme).to eq scheme
        end
    end

    it "ignores an unrecognized scheme without discarding other preferences" do
      file_options root, %({"control_scheme": "future", "motion": false, "flicker": false, "bar_color": "bands", "mouse": false})
      options = Options.read root

      expect(options.control_scheme).to be_nil
      expect(options.effective_control_scheme).to eq ControlScheme::Traditional
      expect(options.motion?).to be_false
      expect(options.flicker?).to be_false
      expect(options.bar_color).to eq Options::BarColor::Bands
      expect(options.mouse?).to be_false
    end

    it "treats null and non-string scheme values as unchosen" do
      ["null", "3", "[]", "{}"].each do |raw|
        file_options root, %({"control_scheme": #{raw}, "motion": false})
        options = Options.read root

        expect(options.control_scheme).to be_nil
        expect(options.motion?).to be_false
      end
    end
  end

  describe "the setting accessors" do
    it "reads and writes the nullable enum deliberately" do
      options = Options.new

      expect(options["control_scheme"]).to be_nil
      expect(options["control_scheme"] = "modern").to eq "modern"
      expect(options.control_scheme).to eq ControlScheme::Modern
      expect(options["control_scheme"]).to eq "modern"
      expect(options["control_scheme"] = nil).to be_nil
      expect(options.control_scheme_chosen?).to be_false
    end

    it "round-trips the selected value in the conventional JSON form" do
      options = Options.new
      options.control_scheme = ControlScheme::Modern
      options.motion = false
      options.write root

      expect(saved_options(root)["control_scheme"].as_s).to eq "modern"
      back = Options.read root
      expect(back.control_scheme).to eq ControlScheme::Modern
      expect(back.motion?).to be_false
    end

    it "writes and reads null while no scheme has been chosen" do
      Options.new.write root

      expect(saved_options(root)["control_scheme"].as_nil).to be_nil
      expect(Options.read(root).control_scheme_chosen?).to be_false
    end

    it "offers two choices and resolves an unchosen form row to Traditional" do
      setting = Options::SETTINGS.find!(&.key.== "control_scheme")
      form = Roguelike::Ui::OptionsScreen.form_for Options.new, Roguelike::Tester::ANONYMOUS

      expect(setting.choices).to eq [{"traditional", "Traditional"}, {"modern", "Modern"}]
      expect(form["control_scheme"]).to eq "traditional"
    end
  end
end
