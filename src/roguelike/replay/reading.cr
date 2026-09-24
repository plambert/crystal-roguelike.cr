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
      def self.read(path : Path | String) : Reading
        where = Path.new path
        found = File.read_lines where
        found.pop if found.last?.try &.blank?
        raise Error.new "#{where} is empty" if found.empty?

        new where, *sorted(where, found)
      end

      # The lines of *found*, each put where it belongs.
      private def self.sorted(where : Path, found : Array(String))
        header = nil.as Header?
        records = [] of Act | Check
        footer = nil.as Footer?
        truncated = false
        ignored = 0

        found.each_with_index do |line, index|
          next if line.blank?

          kind = kind_of line
          unless kind
            raise Error.new "#{where}:#{index + 1} is not JSON" unless index == found.size - 1

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

        raise Error.new "#{where} has no header" unless header
        raise Error.new "#{where} is format #{header.format}, and this build reads #{FORMAT}" if header.format > FORMAT

        {header, records, footer, truncated, ignored}
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
