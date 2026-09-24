require "digest/sha256"
require "json"

module Roguelike
  # One string saying what a run is, the same in every process.
  #
  # A replay is checked by playing it again and comparing fingerprints turn
  # by turn. Two runs that agree at turn 40 and differ at turn 50 put the
  # fault in those ten turns, which is a place to look rather than "the
  # ending was wrong".
  #
  # That only works if the value depends on the state and on nothing else.
  # Nothing here reaches `Object#hash`: Crystal seeds its hasher afresh in
  # every process, so a value built from it differs between two runs of the
  # same replay for no reason a person could find.
  #
  # The game already writes itself out. `Game` includes `JSON::Serializable`
  # and `Save` puts a whole run in one file. This digests that rather than
  # walking a run a second way, so a field added to a save is in the
  # fingerprint the day it is added, and a field left out of a save is left
  # out of both.
  module Fingerprint
    # What the digest is called in the value itself.
    #
    # A fingerprint reads `sha256:1b7c…`. The value says what made it, so a
    # person holding a replay line knows what to check it with rather than
    # guessing from its length, and a later change of algorithm is visible
    # in the old values rather than silent.
    ALGORITHM = "sha256"

    # The fingerprint of *subject*.
    def self.of(subject : JSON::Serializable) : String
      digest canonical(subject)
    end

    # The fingerprint of the canonical JSON *text*.
    #
    # The whole digest is kept: 256 bits, 64 hex characters. Cutting it short
    # would save thirty-odd bytes on a line a replay writes once every
    # twenty-five turns, and it would cost the thing a person wants when a
    # replay does desync, which is to check the number by hand: `#canonical`
    # written to a file and run through `shasum -a 256` answers exactly this.
    # A shortened value has to be explained before it can be checked.
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
    # declared, which is stable, but a `Hash` writes in the order it was
    # filled. Several reach the file: the floors of a world, the creatures,
    # the litter, the lights and the fixtures of a floor, the letters of a
    # pack, the slots of an equipment set, the squares a character remembers,
    # and the appearances a run rolled. Every one of them is filled in an
    # order that follows from the seed and the moves, so two runs that took
    # the same moves fill them alike. Sorting costs one pass and makes the
    # value a function of what the state is rather than of how it got there,
    # which is a weaker thing to have to be sure of.
    #
    # Numbers are copied as they were written rather than read into a number
    # and written again. A run's seed is a `UInt64` and the larger half of
    # that range does not fit in the `Int64` a JSON parser reads into.
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

    # Writes an array to *io*. The order of an array is the state's own.
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
