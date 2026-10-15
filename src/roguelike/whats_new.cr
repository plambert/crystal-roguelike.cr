require "../roguelike"

module Roguelike
  # What changed since the version a person last ran.
  #
  # The text is `NEWS.md`, read when the game is compiled, so a binary
  # carries the news for every release up to its own. The title screen shows
  # it and `--whats-new` prints it.
  #
  # The version that last ran is kept in a file in the state directory. A
  # person who has run nothing before, or who has not upgraded, is shown the
  # newest release alone.
  module WhatsNew
    # `NEWS.md` as it was when this binary was built.
    NEWS = {{ read_file("#{__DIR__}/../../NEWS.md") }}

    # What the last-run file is called under the game's state directory.
    FILE = "last-version"

    # One kind of paragraph in a release's section.
    enum Kind
      Paragraph
      Bullet
      Heading
    end

    # A paragraph, a bullet or a heading, with the Markdown taken out.
    record Block, kind : Kind, text : String

    # One release's entry.
    record Section, version : String, date : String, blocks : Array(Block)

    # One line to draw. A heading line is drawn bold.
    record Line, text : String, heading : Bool = false

    # The sections of *news*, newest first.
    #
    # Anything before the first `## [X.Y.Z]` line is not a release and is
    # left out.
    def self.sections(news : String = NEWS) : Array(Section)
      found = [] of Section
      blocks = nil.as(Array(Block)?)

      news.each_line do |line|
        if match = line.match /\A## \[([^\]]+)\](?: - (.*))?\z/
          blocks = [] of Block
          found << Section.new match[1], match[2]?.to_s.strip, blocks
          next
        end

        into = blocks
        next unless into

        text = line.strip.delete('`')
        if text.empty?
          into << Block.new Kind::Paragraph, "" unless into.empty? || into.last.text.empty?
        elsif text.starts_with? "### "
          into << Block.new Kind::Heading, text.lchop("### ")
        elsif text.starts_with? "* "
          into << Block.new Kind::Bullet, text.lchop("* ")
        elsif (last = into.last?) && !last.text.empty? && !last.kind.heading?
          into[-1] = Block.new last.kind, "#{last.text} #{text}"
        else
          into << Block.new Kind::Paragraph, text
        end
      end

      found.each { |one| one.blocks.pop if one.blocks.last?.try(&.text.empty?) }
      found
    end

    # The sections to show a person who last ran *last*.
    #
    # Every section newer than *last*, or the newest one when there is none
    # newer or nothing is known.
    def self.since(last : String?, from : Array(Section) = sections) : Array(Section)
      return from.first(1) unless last

      fresh = from.select { |one| Update.newer? one.version, last }
      fresh.empty? ? from.first(1) : fresh
    end

    # *sections* as lines no wider than *width*.
    def self.lines(sections : Array(Section), width : Int32) : Array(Line)
      drawn = [] of Line

      sections.each_with_index do |one, index|
        drawn << Line.new "" unless index.zero?
        drawn << Line.new(one.date.empty? ? one.version : "#{one.version} - #{one.date}", heading: true)
        drawn << Line.new ""

        one.blocks.each do |block|
          case block.kind
          in .heading?   then drawn << Line.new(block.text, heading: true)
          in .paragraph? then drawn.concat wrap(block.text, width, "", "")
          in .bullet?    then drawn.concat wrap(block.text, width, "* ", "  ")
          end
        end
      end

      drawn
    end

    # *sections* as text, one line to a row.
    def self.text(sections : Array(Section), width : Int32 = 78) : String
      String.build do |io|
        lines(sections, width).each { |line| io.puts line.text }
      end
    end

    # Breaks *text* at spaces into lines no wider than *width*. The first
    # carries *first* and every other *rest*.
    private def self.wrap(text : String, width : Int32, first : String, rest : String) : Array(Line)
      return [Line.new ""] if text.empty?

      made = [] of Line
      current = first

      text.split(' ').each do |word|
        if current.size > rest.size && current.size + 1 + word.size > width
          made << Line.new current
          current = rest + word
        else
          current += (current.size > rest.size && current != first ? " " : "") + word
        end
      end

      made << Line.new current
      made
    end

    # The version that last ran, kept in a file.
    class LastRun
      # Where the version is kept.
      getter path : Path

      def initialize(root : Path)
        @path = root / FILE
      end

      # The version on file, or `nil` when there is none.
      def version : String?
        File.read(@path).split.first?
      rescue File::Error
        nil
      end

      # Writes *version* down, unless it is there already.
      def record(version : String) : Nil
        return if self.version == version

        Dir.mkdir_p @path.parent
        File.write @path, "#{version} #{Time.utc.to_rfc3339}\n"
      end
    end

    # The sections to show this run, and the record that this version ran.
    #
    # *record* is false for a run that writes nothing down.
    def self.arrive(last_run : LastRun, record : Bool = true,
                    current : String = VERSION) : Array(Section)
      shown = since last_run.version
      last_run.record current if record
      shown
    end
  end
end
