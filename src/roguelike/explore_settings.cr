require "json"
require "../roguelike"

module Roguelike
  module Explore
    # How explore chooses where to go, and what stops a walk of it.
    #
    # The defaults are the explore the game has always had. The first group
    # changes which squares the character walks to. `Explore.route` and
    # `Explore.going?` read it. The second group changes only when a walk of
    # `X` stops, and `Game#stride` reads it. A travel and a visit keep their
    # own stops.
    #
    # The settings belong to the run. `Game#explore_settings` holds them, a
    # save keeps them, and `Action::Configure` changes them, so a replay
    # walks the same squares. `options.json` holds the settings a new
    # character starts with.
    struct Settings
      include JSON::Serializable

      # The values a number setting may take.
      RANGES = {
        "reach"  => 0..24,
        "pocket" => 1..Chambers::BEHIND,
      }

      # The stops `stop=` names, each with the setting it turns on.
      STOPS = {
        "creature" => "stop_creature",
        "hurt"     => "stop_hurt",
        "attacked" => "stop_attacked",
        "item"     => "stop_item",
        "message"  => "stop_message",
        "stairs"   => "stop_stairs",
      }

      # What a setting holds.
      alias Value = Bool | Int32

      # How many steps off a pocket can be and still come before a nearer
      # square. Zero ranks every square by distance alone.
      property reach : Int32 = REACH

      # The most unseen squares behind a frontier square that still count as
      # a pocket. A larger space counts as open ground.
      property pocket : Int32 = Chambers::BEHIND

      # Whether explore walks to gold the character remembers.
      property? gold : Bool = true

      # Whether explore walks to what automatic pickup takes, such as the
      # quiver's ammunition.
      property? pickup : Bool = true

      # Whether explore walks to an item seen from too far off to read, once
      # nothing is left to see.
      property? unread : Bool = true

      # Whether explore sees the whole of a room before it leaves.
      property? rooms : Bool = true

      # Whether explore follows a passage to its end once it is in one.
      property? passages : Bool = true

      # Whether a creature coming into view stops the walk.
      property? stop_creature : Bool = true

      # Whether losing hit points stops the walk.
      property? stop_hurt : Bool = true

      # Whether a creature attacking the character stops the walk, hit or
      # miss.
      property? stop_attacked : Bool = false

      # Whether an item not seen before coming into sight stops the walk.
      property? stop_item : Bool = true

      # Whether a line in the log stops the walk.
      property? stop_message : Bool = true

      # Whether finding the stairs down stops the walk.
      property? stop_stairs : Bool = false

      def initialize
      end

      # Whether every number is in its range.
      def valid? : Bool
        RANGES.all? { |key, range| range.includes? self[key].as(Int32) }
      end

      # Whether these are the defaults.
      def default? : Bool
        self == Settings.new
      end

      # What *key* holds. Raises `KeyError` for a key that is no setting.
      def [](key : String) : Value
        {% for ivar in @type.instance_vars %}
          return @{{ ivar.name }} if key == {{ ivar.name.stringify }}
        {% end %}

        raise KeyError.new "no explore setting #{key.inspect}"
      end

      # Sets what *key* holds. Raises `KeyError` for a key that is no
      # setting, and `ArgumentError` for a value of the wrong kind.
      def []=(key : String, value : Value) : Value
        {% for ivar in @type.instance_vars %}
          if key == {{ ivar.name.stringify }}
            unless value.is_a? {{ ivar.type }}
              raise ArgumentError.new "#{key} holds a #{{{ ivar.type.stringify }}}"
            end

            return @{{ ivar.name }} = value
          end
        {% end %}

        raise KeyError.new "no explore setting #{key.inspect}"
      end

      # Every key, in the order the fields are declared.
      def self.keys : Array(String)
        {{ @type.instance_vars.map(&.name.stringify) }}
      end

      # The settings *text* gives, over *base*.
      #
      # *text* is a list of `key=value` pairs split by commas, such as
      # `reach=2,gold=off`. A number takes digits, and a toggle takes `on`,
      # `off`, `true`, `false`, `yes` or `no`. `stop=` names the stops to
      # keep, joined by `+`, and turns every other stop off, so
      # `stop=attacked+stairs` stops only for those two. `stop=none` turns
      # every stop off. `default` puts everything back first.
      #
      # Raises `ArgumentError` with the reason for anything else.
      def self.parse(text : String, base : Settings = Settings.new) : Settings
        found = base
        text.split(',', remove_empty: true).each do |pair|
          pair = pair.strip
          next found = Settings.new if pair == "default"

          key, equals, value = pair.partition '='
          raise ArgumentError.new "#{pair.inspect} is not key=value" if equals.empty?

          key = key.strip.tr "-", "_"
          value = value.strip
          next found = stopping(found, value) if key == "stop"

          held = found[key]?
          raise ArgumentError.new "no explore setting #{key.inspect}" if held.nil?

          found[key] = parsed key, value, held
        end

        raise ArgumentError.new "a number is out of range in #{text.inspect}" unless found.valid?

        found
      end

      # What *key* holds, or `nil` for a key that is no setting.
      def []?(key : String) : Value?
        self[key]
      rescue KeyError
        nil
      end

      # *value* read for *key*, which now holds *held*.
      private def self.parsed(key : String, value : String, held : Value) : Value
        if held.is_a? Int32
          number = value.to_i?
          raise ArgumentError.new "#{key} takes a number, not #{value.inspect}" unless number

          return number
        end

        case value.downcase
        when "on", "true", "yes"  then true
        when "off", "false", "no" then false
        else
          raise ArgumentError.new "#{key} takes on or off, not #{value.inspect}"
        end
      end

      # *base* with only the stops *names* lists turned on.
      private def self.stopping(base : Settings, names : String) : Settings
        found = base
        wanted = names == "none" ? [] of String : names.split('+', remove_empty: true).map(&.strip)
        wanted.each do |name|
          raise ArgumentError.new "no stop #{name.inspect}" unless STOPS.has_key? name
        end

        STOPS.each { |name, key| found[key] = wanted.includes? name }
        found
      end
    end
  end
end
