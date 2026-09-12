# A window over a field of cells, to look at.
#
#     crystal run examples/cell_grid.cr
#
# Arrows, page keys, Home and End move the camera. The wheel scrolls. The
# pointer names the cell under it. Q leaves.
#
# Moves with `CellGrid` when it goes to termbuf-widgets.cr.

require "../src/roguelike/termbuf_ext/cell_grid"

alias Widgets = TermBuf::Widgets
alias Style = TermBuf::Style

FIELD = 200

# A checkerboard is the cheapest thing to read a camera off by eye, and the
# hundreds are marked so it is clear where in the field the window is.
def paint(view : TermBuf::View, x : Int32, y : Int32) : Nil
  dark = Style::DEFAULT.fg TermBuf::Color.rgb(0x44, 0x48, 0x52)
  lit = Style::DEFAULT.fg TermBuf::Color.rgb(0x88, 0x99, 0xBB)
  mark = Style::DEFAULT.fg TermBuf::Color.rgb(0xFF, 0xAA, 0x44)

  if x % 10 == 0 && y % 10 == 0
    view.write_char 0, 0, '+', mark
    return
  end

  view.write_char 0, 0, (x + y).even? ? '#' : '.', (x + y).even? ? lit : dark
end

TermBuf::Terminal.open do |terminal|
  terminal.enable TermBuf::Tty::MOUSE_SGR_ANY

  cells = Widgets::Cells.from FIELD, FIELD, ->(x : Int32, y : Int32) { {x, y} }
  grid = Widgets::CellGrid.new cells
  grid.takes_focus = true
  grid.on_draw = ->(view : TermBuf::View, x : Int32, y : Int32, _held : {Int32, Int32}) do
    paint view, x, y
    nil
  end

  framed = Widgets::Panel.new(
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow,
    direction: Widgets::Layout::Direction::Row,
    border: Widgets::Border.plain(title: " #{FIELD}x#{FIELD} "))
  framed.add grid, Widgets::Scrollbar.new(grid)

  status = Widgets::Label.new ""
  root = Widgets::Panel.new(
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow)
  root.add framed, status

  size = terminal.size
  bounds = TermBuf::Rect.full size.columns, size.rows
  app = Widgets::App.new terminal, root, bounds, terminal.events, terminal.policy
  app.focus.focus grid

  leaving = false
  quit = Widgets::Bindings.build do |keys|
    keys.bind TermBuf::Key.parse("Q"), "leave",
      ->(_context : Widgets::Context) { leaving = true; nil }
  end
  app.keymap = app.keymap.merge quit

  under = "—"
  app.on_event = ->(event : TermBuf::Event) do
    case event
    when TermBuf::Events::Resize
      app.resize TermBuf::Rect.full(event.size.columns, event.size.rows)
    when TermBuf::Events::Mouse
      spot = grid.cell_at_screen event.x, event.y
      under = spot ? "#{spot[0]}, #{spot[1]}" : "—"
    end
    nil
  end

  # One layout before the first status line, so it reports the window it is
  # in rather than the nothing it had before anything was measured.
  app.frame { }

  loop do
    status.text = "camera #{grid.scroll_x}, #{grid.scroll_y}   " \
                  "window #{grid.viewport_size[0]}x#{grid.viewport_size[1]}   " \
                  "pointer #{under}   arrows/wheel to move, Q to leave"

    app.frame { }
    terminal.paint

    break if leaving
    break unless app.wait
  end
end
