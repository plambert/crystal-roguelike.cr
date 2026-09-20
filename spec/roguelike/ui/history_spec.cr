require "../../spec_helper"

Spectator.describe "the box of messages" do
  # Where a notch of the wheel lands inside the box on an eighty by
  # twenty-four window.
  INSIDE = {20, 10}

  # A run with *count* messages said and every held page read.
  def talkative(count : Int32 = 40) : Playing::Run
    run = Playing.open
    run.clear_monsters
    count.times { |number| run.game.say "Something number #{number} happened." }
    run.play.refresh
    run.render

    while run.pager.holding?
      run.press "."
    end

    run
  end

  # The box on *run*.
  def box(run : Playing::Run) : Roguelike::Ui::HistoryPane
    run.play.history
  end

  describe "Ctrl+P" do
    it "puts the box up" do
      run = talkative

      run.press "Ctrl+P"

      expect(box(run).showing?).to be_true
    end

    it "holds every message of the run" do
      run = talkative 5

      run.press "Ctrl+P"

      expect(box(run).lines.first).to contain "dungeon"
      expect(box(run).lines.last).to eq "Something number 4 happened."
    end

    it "opens on the newest message" do
      run = talkative

      run.press "Ctrl+P"

      expect(run.text).to contain "Something number 39 happened."
      expect(run.text).not_to contain "Something number 0 happened."
    end

    it "takes the box down again" do
      run = talkative
      run.press "Ctrl+P"

      run.press "Ctrl+P"

      expect(box(run).showing?).to be_false
    end

    it "says so when nothing has happened yet" do
      run = Playing.open
      run.game.log.clear
      run.play.refresh

      run.press "Ctrl+P"

      expect(box(run).lines).to eq [Roguelike::Ui::HistoryPane::EMPTY]
    end

    # A message longer than the box is a message with its end missing.
    it "wraps a message rather than cutting it" do
      run = Playing.open
      run.game.say "A single message that runs on far past the width of the " \
                   "box it is shown in, and then some more besides, so that " \
                   "it cannot fit on one row however wide the window is."
      run.play.refresh

      run.press "Ctrl+P"

      expect(box(run).lines.size).to be > run.game.log.size
    end
  end

  describe "the keys inside it" do
    it "walks the character nowhere" do
      run = talkative
      start = run.at
      run.press "Ctrl+P"

      run.press "j"
      run.press "l"

      expect(run.at).to eq start
    end

    it "scrolls back a line at a time" do
      run = talkative
      run.press "Ctrl+P"
      at = box(run).list.scroll

      run.press "k"

      expect(box(run).list.scroll).to eq at - 1
    end

    it "scrolls a window at a time" do
      run = talkative
      run.press "Ctrl+P"
      at = box(run).list.scroll

      run.press "PageUp"

      expect(box(run).list.scroll).to eq at - box(run).page
    end

    it "goes to the oldest message and back to the newest" do
      run = talkative
      run.press "Ctrl+P"

      run.press "Home"
      expect(box(run).list.scroll).to eq 0

      run.press "End"
      expect(run.text).to contain "Something number 39 happened."
    end

    it "scrolls on a notch of the wheel" do
      run = talkative
      run.press "Ctrl+P"
      at = box(run).list.scroll

      run.wheel *INSIDE, up: true

      expect(box(run).list.scroll).to be < at
    end

    it "closes on Escape" do
      run = talkative
      run.press "Ctrl+P"

      run.press "Escape"

      expect(box(run).showing?).to be_false
    end

    it "closes on q without drinking anything" do
      run = talkative
      run.press "Ctrl+P"

      run.press "q"

      expect(box(run).showing?).to be_false
      expect(run.menu.showing?).to be_false
    end
  end

  describe "while it is up" do
    it "holds the keyboard" do
      run = talkative
      run.press "Ctrl+P"

      expect(run.play.modal?).to be_true
    end

    it "gives the keys back when it closes" do
      run = talkative
      start = run.at
      run.press "Ctrl+P"
      run.press "Escape"

      run.press "l"

      expect(run.at).to eq({start[0] + 1, start[1]})
    end
  end
end
