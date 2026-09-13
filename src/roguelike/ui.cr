require "termbuf-widgets"
require "./termbuf_ext/cell_grid"
require "./termbuf_ext/menu"
require "./termbuf_ext/pager"
require "./termbuf_ext/prompt"
require "./termbuf_ext/ramp"

# Everything drawn on the screen.
#
# The aliases here are the ones every file under `Ui` uses. Spelling them once
# keeps a widget name short at each use.
module Roguelike::Ui
  alias Widgets = TermBuf::Widgets
  alias Layout = TermBuf::Widgets::Layout
  alias Style = TermBuf::Style
  alias Rect = TermBuf::Rect
end

require "./direction"
require "./attributes"
require "./item"
require "./game"
require "./floor"
require "./ui/palette"
require "./ui/flicker"
require "./ui/keys"
require "./ui/map_pane"
require "./ui/examine_pane"
require "./ui/nearby_pane"
require "./ui/examiner"
require "./ui/pointer"
require "./ui/status_line"
require "./ui/console_pane"
require "./ui/placard"
require "./ui/placards"
require "./ui/play"
require "./ui/screen"
