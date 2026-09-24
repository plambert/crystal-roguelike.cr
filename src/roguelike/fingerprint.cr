require "digest/sha256"
require "json"

module Roguelike
  # What a game is, as one string, the same in every process.
  #
  # A replay is checked by playing it again and comparing fingerprints turn
  # by turn. Suppose two games agree at turn 40 and differ at turn 50. The
  # fault is then in those ten turns, which is a smaller thing to search
  # than the whole game.
  #
  # That works only if the value depends on the state and on nothing else.
  # Nothing here uses `Object#hash`. Crystal seeds its hasher afresh in every
  # process. A value built from it differs between two plays of one replay,
  # and the difference has no cause in the game.
  #
  # The game is already written out in full. `Game` includes
  # `JSON::Serializable`, and `Save` puts a whole game in one file. This
  # module digests that output rather than walking a game a second way. A
  # field added to a save is therefore in the fingerprint from the day it is
  # added. A field left out of a save is in neither.
  module Fingerprint
    # What the digest is called in the value itself.
    #
    # A fingerprint is `sha256:1b7c…`. The name of the algorithm is in the
    # value. A person holding a replay line then knows which algorithm to
    # check it with, and does not have to guess from the length. A later
    # change of algorithm is also visible in the old values.
    ALGORITHM = "sha256"

    # The fingerprint of *subject*.
    def self.of(subject : JSON::Serializable) : String
      digest canonical(subject)
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
    # and the appearances a game rolled. Each one is filled in an order that
    # follows from the seed and the moves, so two games on the same moves fill
    # them alike. Sorting costs one pass. The value is then a function of
    # what the state is rather than of how the state was reached, and that is
    # the weaker thing to depend on.
    #
    # Numbers are copied as they were written rather than read into a number
    # and written again. A game's seed is a `UInt64`. The larger half of that
    # range does not fit in the `Int64` a JSON parser reads into.
    def self.canonical(text : String) : String
      String.build { |canonical| write JSON::PullParser.new(text), canonical }
    end

    # Writes whatever *pull* is looking at to *io*, canonically.
    private def self.write(pull : JSON::PullParser, io : IO) : Nil
      case pull.kind
      when .null?
        pull.read_null
        io << "null"
      when .bool?
        io << pull.read_bool
      when .int?, .float?
        io << pull.read_raw
      when .string?
        pull.read_string.to_json io
      when .begin_array?
        write_array pull, io
      when .begin_object?
        write_object pull, io
      else
        pull.raise "expected a value, found #{pull.kind}"
      end
    end

    # Writes an array to *io*. The order of an array is left as it is.
    private def self.write_array(pull : JSON::PullParser, io : IO) : Nil
      io << '['
      first = true

      pull.read_array do
        io << ',' unless first
        first = false
        write pull, io
      end

      io << ']'
    end

    # Writes an object to *io* with its fields in order by name.
    private def self.write_object(pull : JSON::PullParser, io : IO) : Nil
      fields = [] of {String, String}

      pull.read_object do |name|
        fields << {name, String.build { |value| write pull, value }}
      end

      fields.sort_by! &.[0]

      io << '{'
      fields.each_with_index do |(name, value), index|
        io << ',' if index > 0
        name.to_json io
        io << ':'
        io << value
      end
      io << '}'
    end
  end
end
