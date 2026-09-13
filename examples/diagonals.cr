# Shallow diagonals in a terminal, four ways, to see which your terminal and
# font actually draw.
#
#     crystal run examples/diagonals.cr
#
# A terminal cell is about twice as tall as it is wide, so a line of `╲` is a
# 1:1 diagonal in cells and looks like 63° on screen. A line that looks like
# 45° has to travel two cells across for every one down. Prints to stdout
# rather than taking the terminal over, so it can be piped and read.

require "termbuf"

alias Widths = TermBuf::Unicode

ROWS    =  6
COLUMNS = 24

# One cell across per row: 1:1 in cells, steep on screen.
def steep : Array(String)
  Array.new(ROWS) { |row| " " * row + "╲" }
end

# Two half-strokes to a cell. Unicode 13.0, so a font is more likely to have
# it — but the slope is the same 1:1, drawn as two shorter strokes.
def halved : Array(String)
  lines = Array.new(ROWS * 2) { "" }

  ROWS.times do |row|
    lines[row * 2] = " " * row + "🮢"
    lines[row * 2 + 1] = " " * row + "🮡"
  end

  lines
end

# Two cells across per row, which is the ratio that looks like 45°. Unicode
# 16.0, from 2024, so font coverage is thin and it draws correctly only on a
# terminal that renders box glyphs itself.
def shallow : Array(String)
  Array.new(ROWS) { |row| " " * (row * 2) + "🯒🯓" }
end

# Braille as a 2 by 4 grid of dots per cell. A dot is half a cell across and a
# quarter down, which on a cell twice as tall as it is wide comes out square,
# so one dot across per dot down is a line that looks like 45°.
DOTS = { {0x01, 0x08}, {0x02, 0x10}, {0x04, 0x20}, {0x40, 0x80} }

def braille : Array(String)
  height = ROWS * 4
  cells = Array.new(ROWS) { Array.new(COLUMNS, 0) }

  height.times do |step|
    x = step
    y = step
    next if x >= COLUMNS * 2

    cells[y // 4][x // 2] |= DOTS[y % 4][x % 2]
  end

  cells.map { |row| String.build { |io| row.each { |bits| io << (0x2800 + bits).chr } } }
end

def show(title : String, sample : String, lines : Array(String)) : Nil
  width = Widths.string_width sample
  clusters = Widths.graphemes(sample).size

  puts
  puts "#{title}  —  #{sample}  #{codepoints sample}"
  puts "  #{clusters} cluster(s), #{width} column(s) by the tables"
  puts
  lines.each { |line| puts "    #{line}" }
end

def codepoints(text : String) : String
  text.codepoints.map { |point| "U+%04X" % point }.join " "
end

puts "Shallow diagonals. If a box below is blank, or the columns do not line"
puts "up, this terminal or this font does not draw that set."

show "1:1, one cell per row", "╲", steep
show "1:1 in half-strokes, Unicode 13", "🮢🮡", halved
show "2:1, two cells per row, Unicode 16", "🯒🯓", shallow
show "braille, 2 by 4 dots per cell", "⠑⠑", braille

puts
puts "A run of each, to check they join:"
puts "    #{"╲" * 12}   #{"🯒🯓" * 6}   #{"🮢🮡" * 6}"
puts
