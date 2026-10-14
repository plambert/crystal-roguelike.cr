require "../../spec_helper"

Spectator.describe "dragging the map with the right button" do
  alias Action = TermBuf::Input::Mouse::Action
  alias Button = TermBuf::Input::Mouse::Button

  # A run on a field far larger than the window.
  def field : Playing::Run
    Playing.open Playing.field(200, 80)
  end

  # Where the character is drawn.
  def character_cell(run : Playing::Run) : {Int32, Int32}
    run.map.screen_of(*run.at) || raise "the character is off the map"
  end

  it "moves the view with the pointer" do
    run = field
    before = run.map.camera
    from = character_cell run

    run.right_drag from, {from[0] - 10, from[1] - 4}

    expect(run.map.camera).to eq({before[0] + 10, before[1] + 4})
  end

  it "keeps the square it started on under the pointer while the button is held" do
    run = field
    from = character_cell run
    square = run.map.cell_at_screen(*from)

    run.mouse Button::Right, Action::Press, *from
    run.mouse Button::Right, Action::Motion, from[0] - 7, from[1] + 3

    expect(run.map.cell_at_screen from[0] - 7, from[1] + 3).to eq square
  end

  it "leaves the view where it was dragged, and moves nobody" do
    run = field
    start = run.at
    from = character_cell run

    run.right_drag from, {from[0] + 12, from[1]}
    dragged = run.map.camera
    run.hover from[0], from[1]

    expect(run.map.camera).to eq dragged
    expect(run.at).to eq start
    expect(run.turn).to eq 0
  end

  it "stops at the edge of the floor" do
    run = field
    from = character_cell run

    run.right_drag from, {from[0] + 500, from[1] + 500}

    expect(run.map.camera).to eq({0, 0})
  end

  it "comes back to the character on the next turn" do
    run = field
    before = run.map.camera
    from = character_cell run

    run.right_drag from, {from[0] - 20, from[1] - 6}
    run.press "."

    expect(run.map.camera).to eq before
  end

  it "comes back to the character on Escape" do
    run = field
    before = run.map.camera
    from = character_cell run

    run.right_drag from, {from[0] - 20, from[1] - 6}
    run.press "Escape"

    expect(run.map.camera).to eq before
    expect(run.turn).to eq 0
  end

  it "follows a character who moved, from where the camera was" do
    run = field
    from = character_cell run
    run.right_drag from, {from[0] - 30, from[1]}

    run.press "l"
    after = run.map.camera

    other = field
    other.press "l"

    expect(after).to eq other.map.camera
  end

  it "draws no route when the right button goes down" do
    run = field
    from = character_cell run
    spot = {from[0] + 3, from[1]}

    run.mouse Button::Right, Action::Press, *spot
    run.mouse Button::Right, Action::Release, *spot

    expect(run.map.highlights).to be_empty
  end

  it "does not pan on motion with no button held" do
    run = field
    before = run.map.camera
    from = character_cell run

    run.hover from[0], from[1]
    run.hover from[0] - 9, from[1]

    expect(run.map.camera).to eq before
  end

  it "does not pan on a left drag" do
    run = field
    before = run.map.camera
    from = character_cell run

    run.mouse Button::Left, Action::Motion, from[0] - 9, from[1]

    expect(run.map.camera).to eq before
  end
end
