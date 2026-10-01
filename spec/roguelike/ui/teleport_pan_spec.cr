require "../../spec_helper"

Spectator.describe "the camera after a teleport" do
  alias Kind = Roguelike::ItemKind
  alias MapPane = Roguelike::Ui::MapPane

  # A run on a field far larger than the window, holding a scroll of minor
  # teleport.
  def holding_scroll(clock : Bool = true) : Playing::Run
    game = Playing.field 200, 80
    game.player.inventory.add Roguelike::Item.new(Kind::TeleportScroll)
    Playing.open game, clock: clock
  end

  # Reads the scroll the run is holding.
  def read_scroll(run : Playing::Run) : Nil
    found = run.game.player.inventory.entries.find do |_letter, item|
      item.kind == Kind::TeleportScroll
    end
    raise "no scroll" unless found

    run.press "r", found[0].to_s
  end

  # Where the camera stands with the character in the middle of the window.
  def centred(run : Playing::Run) : {Int32, Int32}
    held = run.map.camera
    run.map.center_on *run.at
    found = run.map.camera
    run.map.camera = held
    found
  end

  it "pans onto the character a frame at a time" do
    run = holding_scroll
    before = run.map.camera
    start = run.at

    read_scroll run

    expect(run.at).not_to eq start

    expect(run.play.panning?).to be_true
    expect(run.map.camera).to eq before

    seen = [] of {Int32, Int32}
    while run.tick
      seen << run.map.camera
    end

    expect(seen.size).to eq MapPane::PAN_FRAMES
    expect(seen.uniq.size).to be > 1
    expect(run.play.panning?).to be_false
    expect(run.map.camera).to eq centred(run)
  end

  it "slows as it arrives" do
    from = {0, 0}
    to = {80, 40}
    steps = (0..MapPane::PAN_FRAMES).map { |frame| MapPane.eased from, to, frame, MapPane::PAN_FRAMES }
    strides = steps.each_cons_pair.map { |one, other| other[0] - one[0] }.to_a

    expect(steps.first).to eq from
    expect(steps.last).to eq to
    expect(strides.first).to be > strides.last
  end

  it "finishes the pan on a key and then answers the key" do
    run = holding_scroll
    read_scroll run
    run.tick
    expect(run.play.panning?).to be_true
    turn = run.turn

    run.press "."

    expect(run.play.panning?).to be_false
    expect(run.turn).to eq turn + 1
    expect(run.map.camera).to eq centred(run)
    expect(run.armed).to be_empty
  end

  it "lands at once with no clock" do
    run = holding_scroll clock: false

    read_scroll run

    expect(run.play.panning?).to be_false
    expect(run.map.camera).to eq centred(run)
  end

  it "lands at once when nothing moves on a clock" do
    run = holding_scroll
    run.play.flicker.burning = false

    read_scroll run

    expect(run.play.panning?).to be_false
    expect(run.map.camera).to eq centred(run)
    expect(run.armed).to be_empty
  end
end
