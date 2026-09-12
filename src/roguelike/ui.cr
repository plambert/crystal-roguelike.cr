require "termbuf-widgets"
require "./termbuf_ext/cell_grid"

# Everything drawn on the screen.
#
# The aliases here are the ones every file under `Ui` reaches for, spelled
# once so that the widgets read as widgets rather than as a path.
module Roguelike::Ui
  alias Widgets = TermBuf::Widgets
  alias Layout = TermBuf::Widgets::Layout
  alias Style = TermBuf::Style
  alias Rect = TermBuf::Rect
end

require "./direction"
require "./game"
require "./level"
require "./ui/palette"
require "./ui/keys"
require "./ui/map_pane"
require "./ui/examine_pane"
require "./ui/examiner"
require "./ui/pointer"
require "./ui/play"
require "./ui/screen"
