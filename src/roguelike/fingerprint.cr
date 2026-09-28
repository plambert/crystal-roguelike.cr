require "digest/sha256"
require "json"
require "../roguelike"

module Roguelike
  # What a run is, as one string, the same in every process.
  #
  # A replay is checked by playing it again and comparing fingerprints turn
  # by turn. Suppose two runs agree at turn 40 and differ at turn 50. The
  # fault is then in those ten turns, which is a smaller thing to search
  # than the whole run.
  #
  # That works only if the value depends on the state and on nothing else.
  # Nothing here uses `Object#hash`. Crystal seeds its hasher afresh in every
  # process. A value built from it differs between two runs of one replay,
  # and the difference has no cause in the game.
  #
  # The game is already written out in full. `Game` includes
  # `JSON::Serializable`, and `Save` puts a whole run in one file. This
  # module digests that output rather than walking a run a second way. A
  # field added to a save is therefore in the fingerprint from the day it is
  # added. A field left out of a save is in neither. `UNCOUNTED` names the
  # one field a save holds and this leaves out.
  module Fingerprint
    # What the digest is called in the value itself.
    #
    # A fingerprint is `sha256:1b7c…`. The name of the algorithm is in the
    # value. A person holding a replay line then knows which algorithm to
    # check it with, and does not have to guess from the length. A later
    # change of algorithm is also visible in the old values.
    ALGORITHM = "sha256"

    # The fields of a run that are left out of the value.
    #
    # `log` holds the messages a run has written. A message is a rendering of
    # what happened rather than the state itself. Everything a message
    # reports is hashed on its own, which is the hit points, the position,
    # the pack, what the character knows and the turn. A wall bumped writes a
    # line and changes nothing else.
    #
    # The log stays in the save. A person who comes back to a run reads their
    # last lines. It also stays out of this, so a line written outside
    # `Game#perform` no longer parts a run from its own replay.
    #
    # Only the top level is read. A field of this name deeper in the document
    # is hashed the way every other field is.
    UNCOUNTED = ["log"]

    # The fingerprint of *subject*.
    #
    # The canonical form goes into the digest as it is made. A late turn of a
    # long run is a megabyte and a half of JSON, and `#canonical` would hold
    # a second copy of all of it to hand over one string.
    def self.of(subject : JSON::Serializable) : String
      sha = Digest::SHA256.new
      sink = Sink.new sha

      Writer.new.write JSON::PullParser.new(subject.to_json), sink, top: true
      sink.flush

      "#{ALGORITHM}:#{sha.hexfinal}"
    end

    # The fingerprint of the canonical JSON *text*.
    #
    # The whole digest is kept. That is 256 bits and 64 hex characters. A
    # shorter value would save about thirty bytes on a line a replay writes
    # once every twenty-five turns. It would also cost the check a person
    # wants when a replay does desync, which is a check by hand. `#canonical`
    # written to a file and run through `shasum -a 256` gives exactly this
    # value. A shortened value has to be explained first.
    def self.digest(text : String) : String
      "#{ALGORITHM}:#{Digest::SHA256.hexdigest text}"
    end

    # *subject* written as canonical JSON.
    def self.canonical(subject : JSON::Serializable) : String
      canonical subject.to_json
    end

    # :ditto:
    #
    # The canonical form is the same JSON with the fields of every object in
    # order by name. `JSON::Serializable` writes fields in the order they are
    # declared, which is stable. A `Hash` writes in the order it was filled.
    # Several hashes reach the file: the floors of a world, the creatures,
    # the litter, the lights and the fixtures of a floor, the letters of a
    # pack, the slots of an equipment set, the squares a character remembers,
    # and the appearances a run rolled. Each one is filled in an order that
    # follows from the seed and the moves, so two runs on the same moves fill
    # them alike. Sorting costs one pass. The value is then a function of
    # what the state is rather than of how the state was reached, and that is
    # the weaker thing to depend on.
    #
    # Numbers are copied as they were written rather than read into a number
    # and written again. A run's seed is a `UInt64`. The larger half of that
    # range does not fit in the `Int64` a JSON parser reads into.
    #
    # `#of` sends these same bytes to a digest instead of to a string, so the
    # two agree by construction. One spec pins that.
    def self.canonical(text : String) : String
      String.build do |canonical|
        Writer.new.write JSON::PullParser.new(text), canonical, top: true
      end
    end

    # A document written out canonically.
    #
    # An object's fields go out in order by name, so every field has to be
    # read before the first one is written. The fields of an object are held
    # as bytes in one buffer, and each depth of nesting has a buffer of its
    # own. One object is open at each depth at a time, so the buffers serve
    # the whole document. A megabyte of JSON is then a handful of buffers
    # rather than a string for every field in it.
    private class Writer
      OBJECT_OPEN  = '{'.ord.to_u8
      OBJECT_CLOSE = '}'.ord.to_u8
      ARRAY_OPEN   = '['.ord.to_u8
      ARRAY_CLOSE  = ']'.ord.to_u8
      COMMA        = ','.ord.to_u8
      COLON        = ':'.ord.to_u8
      QUOTE        = '"'.ord.to_u8
      BACKSLASH    = '\\'.ord.to_u8

      # The delete byte. A JSON writer spells it out, the way it spells out
      # every other control byte.
      DELETE = 0x7f_u8

      def initialize
        @buffers = [] of IO::Memory
        @fields = [] of {String, Int32, Int32}
      end

      # Writes whatever *pull* is looking at to *io*, canonically.
      #
      # *top* says this is the whole document rather than a value inside it.
      # `UNCOUNTED` is dropped there and nowhere else. *depth* counts the
      # objects this value sits inside, which picks the buffer an object
      # holds its own fields in.
      def write(pull : JSON::PullParser, io : IO, depth : Int32 = 0,
                top : Bool = false) : Nil
        case pull.kind
        when .null?
          pull.read_null
          io << "null"
        when .bool?
          io << pull.read_bool
        when .int?, .float?
          io << pull.read_raw
        when .string?
          quote pull.read_string, io
        when .begin_array?
          write_array pull, io, depth
        when .begin_object?
          write_object pull, io, depth, top
        else
          pull.raise "expected a value, found #{pull.kind}"
        end
      end

      # Writes an array to *io*. The order of an array is left as it is.
      #
      # An array holds nothing back, so it needs no buffer and its elements
      # sit at the depth it does.
      private def write_array(pull : JSON::PullParser, io : IO,
                              depth : Int32) : Nil
        io.write_byte ARRAY_OPEN
        first = true

        pull.read_array do
          io.write_byte COMMA unless first
          first = false
          write pull, io, depth
        end

        io.write_byte ARRAY_CLOSE
      end

      # Writes an object to *io* with its fields in order by name.
      #
      # *top* drops `UNCOUNTED`. Only the whole document passes it.
      private def write_object(pull : JSON::PullParser, io : IO,
                               depth : Int32, top : Bool) : Nil
        held = buffer depth
        mark = held.pos
        base = @fields.size

        pull.read_object do |name|
          next pull.skip if top && UNCOUNTED.includes? name

          at = held.pos
          write pull, held, depth + 1
          @fields << {name, at, held.pos - at}
        end

        # The fields of every open object share one array, and this object's
        # are the ones above `base`. Nothing is pushed while the slice below
        # is in hand, so the array does not take a larger buffer and move
        # them. One array per object would be an allocation for every object
        # in the document.
        fields = Slice.new @fields.to_unsafe + base, @fields.size - base

        # The names of one object are all different, so no two entries
        # compare equal, and the order an unstable sort leaves them in is the
        # only order there is. `Array#sort_by!` maps the array into a second
        # one first, which is another allocation for every object.
        fields.unstable_sort! { |one, other| one[0] <=> other[0] }

        # Nothing writes to `held` from here on, so the bytes stay where the
        # slice says they are. A write could move them, because `IO::Memory`
        # takes a larger buffer when it outgrows the one it has.
        written = held.to_slice

        io.write_byte OBJECT_OPEN
        fields.each_with_index do |(name, at, size), index|
          io.write_byte COMMA if index > 0
          quote name, io
          io.write_byte COLON
          io.write written[at, size]
        end
        io.write_byte OBJECT_CLOSE

        @fields.truncate 0, base
        held.pos = mark
      end

      # The buffer an object *depth* objects deep holds its fields in.
      private def buffer(depth : Int32) : IO::Memory
        while @buffers.size <= depth
          @buffers << IO::Memory.new
        end

        @buffers[depth]
      end

      # Writes *value* to *io* as a quoted JSON string.
      #
      # `String#to_json` builds a `JSON::Builder` for each call, and this
      # writes a hundred thousand names and strings for one late turn. The
      # bytes are the ones a builder would write. `fingerprint_spec.cr`
      # compares the two over every string that needs an escape.
      private def quote(value : String, io : IO) : Nil
        bytes = value.to_slice
        io.write_byte QUOTE

        start = 0
        index = 0

        while index < bytes.size
          byte = bytes.unsafe_fetch index

          if byte < 0x20 || byte == QUOTE || byte == BACKSLASH || byte == DELETE
            io.write bytes[start, index - start]
            io << escaped(byte)
            start = index &+ 1
          end

          index &+= 1
        end

        io.write bytes[start, bytes.size - start]
        io.write_byte QUOTE
      end

      # How a byte that cannot stand for itself is written.
      private def escaped(byte : UInt8) : String
        case byte
        when BACKSLASH then "\\\\"
        when QUOTE     then "\\\""
        when 0x08      then "\\b"
        when 0x0c      then "\\f"
        when 0x0a      then "\\n"
        when 0x0d      then "\\r"
        when 0x09      then "\\t"
        else                "\\u00#{byte < 0x10 ? "0" : ""}#{byte.to_s 16}"
        end
      end
    end

    # An `IO` that hashes what is written to it.
    #
    # `Digest::SHA256` takes bytes rather than an `IO`, and `Writer` writes a
    # brace and a comma at a time. The bytes gather here and go over a block
    # at a time. `#flush` hands over what is left.
    private class Sink < IO
      # How many bytes gather before they are hashed.
      BLOCK = 64 * 1024

      def initialize(@sha : Digest::SHA256)
        @held = Bytes.new BLOCK
        @size = 0
      end

      def write(slice : Bytes) : Nil
        if slice.size >= BLOCK
          flush
          @sha.update slice
          return
        end

        flush if @size + slice.size > BLOCK
        slice.copy_to @held.to_unsafe + @size, slice.size
        @size += slice.size
      end

      def read(slice : Bytes) : NoReturn
        raise IO::Error.new "a digest has nothing to read"
      end

      # Hashes the bytes that have gathered and have not gone over yet.
      def flush : Nil
        return if @size.zero?

        @sha.update @held[0, @size]
        @size = 0
      end
    end
  end
end
