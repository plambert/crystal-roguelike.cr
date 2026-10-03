require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Replay::Viewer do
  alias Verifier = Roguelike::Replay::Verifier
  alias Viewer = Roguelike::Replay::Viewer

  # A viewer on the replay the specs ship with.
  def watching : Viewer
    Viewer.open Recording.golden
  end

  # A run played forward to *acts* actions, without a viewer.
  #
  # `Replay::Verifier` rebuilds the run the same way, and it looks after
  # every action. Two runs at the same action agree only when both looked.
  def forward_to(acts : Int32) : Roguelike::Game
    reading = Recording.read Recording.golden
    game = Verifier.rebuild reading.header

    reading.records.select(Roguelike::Replay::Act).first(acts).each do |act|
      game.perform act.action
      game.look
    end

    game
  end

  describe "opening a file" do
    it "starts before the first action" do
      found = watching

      expect(found.at).to eq 0
      expect(found.turn).to eq 0
      expect(found.trouble).to be_nil
      found.close
    end

    it "holds every action of the file" do
      found = watching

      expect(found.size).to eq found.reading.acts
      expect(found.last_turn).to eq found.acts.last.turn
      found.close
    end
  end

  describe "going forward" do
    it "performs one action at a time" do
      found = watching
      10.times { found.forward }

      expect(found.at).to eq 10
      expect(found.game.fingerprint).to eq forward_to(10).fingerprint
      found.close
    end

    it "plays the whole file with nothing to report" do
      found = watching
      while found.forward
      end

      expect(found.at).to eq found.size
      expect(found.done?).to be_true
      expect(found.trouble).to be_nil
      found.close
    end

    it "answers false at the end" do
      found = watching
      found.goto found.size

      expect(found.forward).to be_false
      found.close
    end
  end

  describe "going back" do
    it "lands where a run played forward lands" do
      found = watching
      10.times { found.forward }
      5.times { found.back }

      expect(found.at).to eq 5
      expect(found.game.turn).to eq forward_to(5).turn
      expect(found.game.fingerprint).to eq forward_to(5).fingerprint
      found.close
    end

    it "answers false at the start" do
      found = watching

      expect(found.back).to be_false
      found.close
    end

    it "goes back to the start and forward again" do
      found = watching
      20.times { found.forward }
      found.goto 0

      expect(found.at).to eq 0
      expect(found.game.fingerprint).to eq forward_to(0).fingerprint

      20.times { found.forward }
      expect(found.game.fingerprint).to eq forward_to(20).fingerprint
      found.close
    end
  end

  describe "going to a turn" do
    it "stops on the first action at or after the turn" do
      found = watching
      found.to_turn 12

      expect(found.turn).to be >= 12
      expect(found.acts[found.at - 2].turn).to be < 12
      found.close
    end

    it "goes to the end for a turn past the file" do
      found = watching
      found.to_turn found.last_turn + 100

      expect(found.at).to eq found.size
      found.close
    end
  end

  # A process id no process holds.
  #
  # The process is run and waited for, so the id is free by the time this
  # answers. A file under it is what a viewer that was killed leaves behind.
  def spent : Int64
    found = {% if flag?(:win32) %} Process.new("cmd.exe", ["/c", "exit"]) {% else %} Process.new("/usr/bin/true") {% end %}
    pid = found.pid
    found.wait
    pid
  end

  describe "the snapshots" do
    it "writes one for the start and takes it away again" do
      found = watching
      where = Viewer.file_at 0

      expect(File.exists? where).to be_true
      found.close
      expect(File.exists? where).to be_false
    end

    it "reads its own file names back" do
      expect(Viewer.owner File.basename(Viewer.file_at 250))
        .to eq Process.pid
    end

    it "reads no name it did not write" do
      expect(Viewer.owner "roguelike-replay.json").to be_nil
      expect(Viewer.owner "some-other-file.json").to be_nil
    end

    it "takes away a file whose process is gone" do
      stale = Path[Dir.tempdir] / "#{Viewer::PREFIX}#{spent}-13#{Viewer::SUFFIX}"
      File.write stale, "{}"

      Viewer.sweep
      expect(File.exists? stale).to be_false
    end

    it "leaves the file of a process that is running" do
      mine = Path[Dir.tempdir] / "#{Viewer::PREFIX}#{Process.pid}-9999#{Viewer::SUFFIX}"
      File.write mine, "{}"

      Viewer.sweep
      expect(File.exists? mine).to be_true
      File.delete mine
    end
  end

  describe "a run this build plays differently" do
    it "reports the first difference and plays on" do
      lines = File.read_lines Recording.golden
      lines.map! do |line|
        next line unless line.starts_with? %({"type":"check")

        check = Roguelike::Replay::Check.from_json line
        Roguelike::Replay::Check.new(check.turn, "0" * 32).to_json
      end

      where = Recording.directory / "differing-#{Random.rand UInt32}.jsonl"
      File.write where, lines.join('\n') + "\n"

      found = Viewer.open where
      while found.forward
      end

      expect(found.at).to eq found.size
      expect(found.trouble).to match /the run differs from the file/
      found.close
    end
  end
end

Spectator.describe "watching a recorded run" do
  alias Play = Roguelike::Ui::Play
  alias Viewer = Roguelike::Replay::Viewer

  # A window on the replay the specs ship with.
  #
  # *clock* gives the application timers a spec fires by hand. Without one
  # the whole file plays inside the press that starts it.
  def watching(clock : Bool = false) : Playing::Run
    Playing.open viewer: Viewer.open(Recording.golden), clock: clock
  end

  # Closes *run* and takes its snapshots away.
  def done(run : Playing::Run) : Nil
    run.viewer.try &.close
  end

  # The viewer *run* is watching.
  def held(run : Playing::Run) : Viewer
    run.viewer.as Viewer
  end

  # The label *run* writes the transport on.
  def banner(run : Playing::Run) : TermBuf::Widgets::Label
    run.screen.banner.as TermBuf::Widgets::Label
  end

  describe "the transport" do
    it "steps forward on l and on the right arrow" do
      run = watching
      run.press "l"
      run.press "Right"

      expect(held(run).at).to eq 2
      done run
    end

    it "steps back on h and on the left arrow" do
      run = watching
      4.times { run.press "l" }
      run.press "h"
      run.press "Left"

      expect(held(run).at).to eq 2
      done run
    end

    it "plays the file on Space" do
      run = watching
      run.press "Space"

      expect(held(run).done?).to be_true
      done run
    end

    it "stops on Space while it is playing" do
      run = watching clock: true
      run.press "Space"
      expect(run.play.playing_back?).to be_true

      run.press "Space"
      expect(run.play.playing_back?).to be_false
      done run
    end

    it "stops when a step is taken" do
      run = watching clock: true
      run.press "Space"
      run.press "l"

      expect(run.play.playing_back?).to be_false
      done run
    end
  end

  describe "the speed" do
    it "starts at the middle of the ladder" do
      run = watching
      expect(run.play.view_speed).to eq Play::VIEW_SPEED
      done run
    end

    it "takes a number" do
      run = watching
      run.press "1"
      expect(run.play.view_speed).to eq 1

      run.press "5"
      expect(run.play.view_speed).to eq 5
      done run
    end

    it "steps up and down on plus and minus" do
      run = watching
      run.press "1"
      run.press "+"
      expect(run.play.view_speed).to eq 2

      run.press "-"
      expect(run.play.view_speed).to eq 1

      run.press "-"
      expect(run.play.view_speed).to eq 1
      done run
    end
  end

  describe "the banner" do
    it "says the turn, the action and the speed" do
      run = watching
      run.press "l"
      text = banner(run).text

      expect(text).to match /turn \d+/
      expect(text).to match /action 1 of #{held(run).size}/
      expect(text).to match /paused/
      expect(text).to match /speed #{run.play.view_speed}/
      done run
    end

    it "says the run is at its end once every action is performed" do
      run = watching
      run.press "Space"

      expect(banner(run).text).to match /end/
      done run
    end

    it "holds no page of messages" do
      run = watching
      run.press "Space"

      expect(run.pager.deferred?).to be_true
      expect(run.pager.holding?).to be_false
      done run
    end

    it "takes a row from the message pane" do
      run = watching
      expect(run.screen.log_rows).to eq Roguelike::Ui::Screen::LOG_ROWS - 1
      done run
    end
  end

  describe "what the keyboard does not reach" do
    it "takes no turn on a movement key that is not east or west" do
      run = watching
      turn = run.turn
      run.press "j"
      run.press "k"

      expect(run.turn).to eq turn
      done run
    end

    it "takes no turn on the keys that act" do
      run = watching
      turn = run.turn
      run.press "."
      run.press ","
      run.press "o"

      expect(run.turn).to eq turn
      done run
    end

    it "reads a square with the examine cursor" do
      run = watching
      run.press "x"

      expect(run.examiner.cursoring?).to be_true
      done run
    end
  end

  describe "what it writes" do
    it "saves nothing" do
      run = watching
      run.press "Space"

      expect(run.store).to be_nil
      done run
    end

    it "records nothing" do
      expect(Roguelike::Replay::Log.pattern).to be_nil

      run = watching
      run.press "Space"

      expect(run.game.fingerprint).to_not be_empty
      done run
    end
  end
end
