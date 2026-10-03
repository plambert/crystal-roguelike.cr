require "compress/gzip"
require "json"
require "../../roguelike"

module Roguelike
  module Replay
    # A replay file that could not be read.
    class Error < Exception
    end

    # One line of a file that is played back, in the order it was written.
    alias Record = Act | Check | Pause | Resume

    # A replay file, read.
    #
    # The header comes first, then the actions, the checkpoints, the pauses
    # and the resumes in the order they were written, then the footer. A file
    # has no footer when the process it was recording went away without one,
    # or when the run is paused, and that is a file this reads rather than
    # refuses.
    #
    # A footer with more lines after it ended one process's share of the
    # run, and a resume carried the run on. Only a footer at the end of the
    # file says how the run ended.
    #
    # A line of a kind this does not know is counted and passed over. The
    # recording format allows two of those, which are a playtester's note and
    # a record of what the screen did. Neither is played back.
    class Reading
      # Where the file is.
      getter path : Path

      # What the run was written down with, and where it started.
      getter header : Header

      # The actions, the checkpoints, the pauses and the resumes, in the
      # order they were written.
      getter records : Array(Record)

      # How the run ended. `nil` for a file with no footer.
      getter footer : Footer?

      # Whether the last line of the file was cut off part way.
      #
      # A process killed while it was writing leaves one of these. Everything
      # before it is whole and is played back.
      getter? truncated : Bool

      # How many lines were of a kind this reader has no use for.
      getter ignored : Int32

      def initialize(@path : Path, @header : Header,
                     @records : Array(Record), @footer : Footer?,
                     @truncated : Bool, @ignored : Int32)
      end

      # The file at *path*, read.
      #
      # *fingerprints* says the values in the file have to be ones this build
      # takes. `script/golden.cr` passes false. It reads the actions out of a
      # file whose fingerprints it is about to write afresh, and those are
      # the values being replaced.
      def self.read(path : Path | String,
                    fingerprints : Bool = true) : Reading
        where = Path.new path
        found = lines where
        found.pop if found.last?.try &.blank?
        raise Error.new "the file is empty" if found.empty?

        new where, *sorted(found, fingerprints)
      end

      # The lines of the file at *where*. A file named `.gz` is unpacked, so a
      # log that arrived as an upload reads where it sits.
      private def self.lines(where : Path) : Array(String)
        return File.read_lines where unless where.extension == ".gz"

        File.open where do |file|
          Compress::Gzip::Reader.open(file, &.gets_to_end).lines
        end
      end

      # The lines of *found*, each put where it belongs.
      private def self.sorted(found : Array(String),
                              fingerprints : Bool = true)
        header = nil.as Header?
        records = [] of Record
        footer = nil.as Footer?
        truncated = false
        ignored = 0

        found.each_with_index do |line, index|
          next if line.blank?

          kind = kind_of line
          unless kind
            raise Error.new "line #{index + 1} is not JSON" unless index == found.size - 1

            truncated = true
            next
          end

          case read = decoded(kind, line)
          in Header then header = read
          in Footer then footer = read
          in Nil    then ignored += 1
          in Record
            records << read
            footer = nil
          end
        end

        raise Error.new "the file has no header" unless header
        if fingerprints && !READS.includes?(header.format)
          raise Error.new refused(header.format)
        end

        {header, records, footer, truncated, ignored}
      end

      # *line*, read as the *kind* it calls itself. `nil` for a kind this
      # reader has no use for.
      private def self.decoded(kind : String, line : String) : Header | Record | Footer | Nil
        case kind
        when "header" then Header.from_json line
        when "act"    then Act.from_json line
        when "check"  then Check.from_json line
        when "pause"  then Pause.from_json line
        when "resume" then Resume.from_json line
        when "footer" then Footer.from_json line
        end
      end

      # Why a file of *format* is not read.
      #
      # Format 1 holds fingerprints taken with the message log in them, and
      # this build leaves the log out. Every checkpoint in such a file
      # differs from what this build takes, so there is nothing in it to
      # check. `--force` does not reach this. It is for a build whose draw
      # sequences moved, where checking anyway says something, and here it
      # would say only that the first checkpoint differs.
      private def self.refused(format : Int32) : String
        if format == 1
          return "the file is format 1, recorded by a build whose " \
                 "fingerprints cover the message log, which this build " \
                 "leaves out. Record the run again to check it"
        end

        "the file is format #{format}, and this build reads " \
        "#{READS.begin} to #{READS.end}"
      end

      # What *line* calls itself. `nil` for a line that is not JSON.
      #
      # `JSON.parse` is not what reads it. That method holds every number it
      # finds as an `Int64`, and a seed is a `UInt64`. A run on a seed above
      # `Int64::MAX` has one in its header, and about half of all seeds are
      # above it. `Kind` reads the one field this wants and steps over the
      # rest without holding any of it.
      private def self.kind_of(line : String) : String?
        Kind.from_json(line).type
      rescue JSON::ParseException
        nil
      end

      # The one field of a line that says which kind of line it is.
      struct Kind
        include JSON::Serializable

        getter type : String?
      end

      # How many actions the file holds.
      def acts : Int32
        @records.count &.is_a?(Act)
      end

      # How many checkpoints the file holds.
      def checks : Int32
        @records.count &.is_a?(Check)
      end

      # How many saves the file holds.
      def pauses : Int32
        @records.count &.is_a?(Pause)
      end

      # How many loads the file holds.
      def resumes : Int32
        @records.count &.is_a?(Resume)
      end

      # The pauses a resume goes back to, past actions written after them.
      #
      # A process that played on after a save and went away without another
      # leaves actions the save does not hold. The resume that follows starts
      # again from the save, so whatever plays the file back keeps the run as
      # it stood at each of these pauses.
      def rewound : Set(Int32)
        acted = 0
        at = {} of Int32 => Int32
        found = Set(Int32).new

        @records.each do |record|
          case record
          when Act    then acted += 1
          when Pause  then at[record.pause] = acted
          when Resume then found << record.pause if at[record.pause]?.try { |was| was < acted }
          end
        end

        found
      end
    end
  end
end
