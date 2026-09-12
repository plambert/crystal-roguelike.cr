# A window over a field of cells, to look at.
#
#     crystal run examples/cell_grid.cr
#
# Arrows, page keys, Home and End move the camera. The wheel scrolls, and so
# does dragging either scrollbar. The pointer names the cell under it. Q
# leaves.
#
# `Demo::Field` is what is being looked at: a 200 by 200 field landmarked with
# guide lines, the coordinates of every crossing, a diagonal and a plus in the
# middle. It is a `Cells` subclass, which is the shape a level in a game has.
#
# Moves with `CellGrid` when it goes to termbuf-widgets.cr.

require "./cell_grid_field"

alias Widgets = TermBuf::Widgets

# The window, the two bars beside it, and the corner where they meet.
def framed(grid : Widgets::CellGrid(Demo::Mark)) : Widgets::Panel
  grow = Widgets::Layout::Sizing.grow

  body = Widgets::Panel.new(
    direction: Widgets::Layout::Direction::Row,
    width: grow, height: grow)
  body.add grid, Widgets::Scrollbar.new(grid)

  # Both bars are up all the time. One that appears only while something is
  # scrolling says where you are exactly when you already know, and nothing
  # the rest of the time.
  footer = Widgets::Panel.new(
    direction: Widgets::Layout::Direction::Row,
    width: grow, height: Widgets::Layout::Sizing.fixed(1))
  footer.add Widgets::Scrollbar.new(grid, Widgets::Scrollbar::Orientation::Horizontal),
    Widgets::Panel.new(width: Widgets::Layout::Sizing.fixed(1))

  panel = Widgets::Panel.new(
    direction: Widgets::Layout::Direction::Column,
    width: grow, height: grow,
    border: Widgets::Border.plain(title: " #{Demo::Field::SIZE}x#{Demo::Field::SIZE} "))
  panel.add body, footer
  panel
end

TermBuf::Terminal.open do |terminal|
  terminal.enable TermBuf::Tty::MOUSE_SGR_ANY

  grid = Widgets::CellGrid.new Demo::Field.new
  grid.takes_focus = true
  grid.on_draw = ->(view : TermBuf::View, _x : Int32, _y : Int32, mark : Demo::Mark) do
    view.write_char 0, 0, mark.glyph, mark.style
    nil
  end

  status = Widgets::Label.new ""
  root = Widgets::Panel.new(
    width: Widgets::Layout::Sizing.grow,
    height: Widgets::Layout::Sizing.grow)
  root.add framed(grid), status

  size = terminal.size
  app = Widgets::App.new terminal, root,
    TermBuf::Rect.full(size.columns, size.rows),
    terminal.events, terminal.policy
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

  # One layout before the first status line, so it reports the window it is in
  # rather than the nothing it had before anything was measured.
  app.frame { }

  loop do
    room = grid.viewport_size
    status.text = "camera #{grid.scroll_x},#{grid.scroll_y}   " \
                  "window #{room[0]}x#{room[1]}   " \
                  "pointer #{under}   arrows/wheel/drag, Q to leave"

    app.frame { }
    terminal.paint

    break if leaving
    break unless app.wait
  end
end
