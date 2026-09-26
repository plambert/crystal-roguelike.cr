require "json"

module Roguelike
  module Replay
    # A replay file that could not be read.
    class Error < Exception
    end

    # A replay file, read.
    #
    # The header comes first, then the actions and the checkpoints in the
    # order they were written, then the footer. A file has no footer when the
    # process it was recording went away without one, and that is a file this
    # reads rather than refuses.
    #
    # A line of a kind this does not know is counted and passed over.
    # `bots/PROTOCOL.md` section 3.1 has two of those, which are a
    # playtester's note and a record of what the screen did. Neither is
    # played back.
    class Reading
      # Where the file is.
      getter path : Path

      # What the run was written down with, and where it started.
      getter header : Header

      # The actions and the checkpoints, in the order they were written.
      getter records : Array(Act | Check)

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
                     @records : Array(Act | Check), @footer : Footer?,
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
        found = File.read_lines where
        found.pop if found.last?.try &.blank?
        raise Error.new "the file is empty" if found.empty?

        new where, *sorted(found, fingerprints)
      end

      # The lines of *found*, each put where it belongs.
      private def self.sorted(found : Array(String),
                              fingerprints : Bool = true)
        header = nil.as Header?
        records = [] of Act | Check
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

          case kind
          when "header" then header = Header.from_json line
          when "act"    then records << Act.from_json line
          when "check"  then records << Check.from_json line
          when "footer" then footer = Footer.from_json line
          else               ignored += 1
          end
        end

        raise Error.new "the file has no header" unless header
        if fingerprints && header.format != FORMAT
          raise Error.new refused(header.format)
        end

        {header, records, footer, truncated, ignored}
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

        "the file is format #{format}, and this build reads #{FORMAT}"
      end

      # What *line* calls itself. `nil` for a line that is not JSON.
      private def self.kind_of(line : String) : String?
        JSON.parse(line)["type"]?.try &.as_s?
      rescue JSON::ParseException
        nil
      end

      # How many actions the file holds.
      def acts : Int32
        @records.count &.is_a?(Act)
      end

      # How many checkpoints the file holds.
      def checks : Int32
        @records.count &.is_a?(Check)
      end
    end
  end
end
