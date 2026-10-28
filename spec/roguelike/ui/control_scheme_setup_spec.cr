require "../../spec_helper"

Spectator.describe Roguelike::Ui::ControlSchemeSetup do
  alias Options = Roguelike::Options
  alias Scheme = Options::ControlScheme
  alias Setup = Roguelike::Ui::ControlSchemeSetup

  after_each { Options.current = nil }

  def temporary_root : Path
    Path[File.tempname("roguelike-controls", nil)].tap do |path|
      at_exit { FileUtils.rm_rf path.to_s }
    end
  end

  def display : Headless::Session
    Headless.open TermBuf::Widgets::Panel.new, 80, 24
  end

  it "saves an explicit choice and preserves the other preferences" do
    root = temporary_root
    options = Options.new
    options.motion = false
    setup = Setup.new root
    session = display
    results = [] of Setup::Result
    changes = [] of Scheme
    setup.on_change = ->(changed : Options) do
      changes << changed.effective_control_scheme
      nil
    end
    setup.show(session.app, options) { |result| results << result }

    expect(Setup.needed?(options)).to be_true
    expect(File.exists?(Options.path(root))).to be_false
    session.press "f"

    expect(results.size).to eq 1
    expect(results.first.accepted?).to be_true
    expect(results.first.saved).to be_true
    expect(results.first.error).to be_nil
    expect(changes).to eq [Scheme::Modern]
    expect(Options.read(root).control_scheme).to eq Scheme::Modern
    expect(Options.read(root).motion?).to be_false
    expect(Setup.needed?(Options.read(root))).to be_false
  end

  it "does not save, apply, or notify after cancellation" do
    root = temporary_root
    options = Options.new
    setup = Setup.new root
    session = display
    results = [] of Setup::Result
    changes = 0
    setup.on_change = ->(changed : Options) { changes += 1 if changed.same?(options); nil }
    setup.show(session.app, options) { |result| results << result }
    session.press "Escape"

    expect(results.size).to eq 1
    expect(results.first.accepted?).to be_false
    expect(changes).to eq 0
    expect(options.control_scheme).to be_nil
    expect(Options.current).to be_nil
    expect(File.exists?(root)).to be_false
  end

  it "keeps the selected scheme in memory and reports a write failure" do
    root = temporary_root
    File.write root, "this is a file, not a directory"
    options = Options.new
    setup = Setup.new root
    session = display
    results = [] of Setup::Result
    setup.show(session.app, options) { |result| results << result }
    session.press "a Enter"

    expect(results.first.accepted?).to be_true
    expect(results.first.saved).to be_false
    expect(results.first.error.to_s).to contain "applies for this session"
    expect(options.control_scheme).to eq Scheme::Traditional
    expect(Options.current).to be options
    expect(File.read(root)).to eq "this is a file, not a directory"
  end

  it "preserves per-run flag values when writing the chosen scheme" do
    root = temporary_root
    Dir.mkdir_p root
    File.write Options.path(root), %({"motion":false,"flicker":true})
    options = Options.arrange root, motion: true, flicker: false
    setup = Setup.new root
    session = display
    results = [] of Setup::Result
    setup.show(session.app, options) { |result| results << result }
    session.press "f"

    saved = Options.read root
    expect(results.first.saved).to be_true
    expect(saved.control_scheme).to eq Scheme::Modern
    expect(saved.motion?).to be_false
    expect(saved.flicker?).to be_true
    expect(options.motion?).to be_true
    expect(options.flicker?).to be_false
  end
end
