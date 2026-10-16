require "termbuf-widgets"

module TermBuf::Widgets
  # Plans a scroll down a list of rows that inserts a sample of the rows
  # between, so a long way reads as scrolling and takes a few frames.
  #
  #     SampledScroll.frames from: 40, to: 300, height: 4, count: 6
  #     # => six frames, each the rows to show, top to bottom
  #
  # Each frame adds a few rows at the bottom and pushes the rest up, the way
  # a terminal scrolls. The rows it adds skip through the stretch between the
  # two ends, so a scroll past three hundred rows inserts a dozen of them. The
  # last *height* rows it adds are the final *height* rows, in order, so the
  # last frame shows exactly where the scroll ends.
  #
  # Offsets name the bottom row a window shows, so the plan holds for a
  # window of any height. A window shrinking while it scrolls shows the last
  # rows of each frame.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`.
  module SampledScroll
    # The rows to show on each frame of a scroll from bottom row *from* down
    # to bottom row *to*. *height* is the height of the window when the
    # scroll ends. *window* is how many rows each frame lists, at least
    # *height*. A window taller than *height* during the scroll shows more of
    # each frame.
    #
    # Each frame inserts at most half of *height* rows, rounded up, so every
    # frame keeps rows the one before showed. There are at most *count*
    # frames, and fewer when there are fewer rows to insert than that. A
    # scroll up, or nowhere, has no frames.
    def self.frames(from : Int32, to : Int32, height : Int32, count : Int32,
                    window : Int32 = height) : Array(Array(Int32))
      planned = [] of Array(Int32)
      return planned if to <= from || count <= 0 || height <= 0

      window = Math.max window, height
      inserted = inserts from, to, height, count
      frames = Math.min count, inserted.size

      stream = (Math.max(from - window + 1, 0)..Math.max(from, 0)).to_a
      done = 0
      (1..frames).each do |frame|
        upto = inserted.size * frame // frames
        stream.concat inserted[done...upto]
        done = upto
        planned << stream.last(window)
      end

      planned
    end

    # The rows a scroll from *from* to *to* inserts, in order. A sample of
    # the stretch between comes first, then the final *height* rows.
    def self.inserts(from : Int32, to : Int32, height : Int32,
                     count : Int32) : Array(Int32)
      return [] of Int32 if to <= from || count <= 0 || height <= 0

      start = Math.max from + 1, to - height + 1
      tail = (start..to).to_a
      gap = start - from - 1
      room = count * Math.max((height + 1) // 2, 1)
      wanted = (room - tail.size).clamp 0, gap

      sample(from + 1, gap, wanted) + tail
    end

    # *wanted* rows spread evenly over the *size* rows from *first*, one from
    # the middle of each equal share.
    def self.sample(first : Int32, size : Int32, wanted : Int32) : Array(Int32)
      return [] of Int32 if wanted <= 0 || size <= 0

      wanted = Math.min wanted, size
      (0...wanted).map { |index| first + ((2 * index + 1) * size) // (2 * wanted) }
    end
  end
end
