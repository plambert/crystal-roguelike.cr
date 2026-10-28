require "json"
require "../roguelike"

module Roguelike
  # The person's preferences, kept in `options.json` in the game's state
  # directory beside `tester.json`.
  #
  # Every property has a default. A file that lacks a key keeps that key's
  # default, so a file written before an option existed still reads. A file
  # that does not parse reads as the defaults.
  #
  # `Options.current` is what the game reads. It is `nil` until the
  # interactive game sets it, so the bot, the trial harness and the specs run
  # on the defaults the code already has. Options are not game state. No
  # replay or fingerprint reads them.
  class Options
    include JSON::Serializable

    # What the file is called.
    FILE = "options.json"

    # How a bar's color follows how full it is.
    enum BarColor
      # The color mixes smoothly between levels.
      Gradient

      # The color steps from one level to the next.
      Bands
    end

    # The movement and interaction keys the person uses.
    enum ControlScheme
      # The existing command letters and hjkl movement.
      Traditional

      # Spatial movement and discoverable action menus.
      Modern
    end

    # Reads a saved scheme without rejecting the other options when it is
    # absent, null, or unrecognized.
    module ControlSchemeValue
      def self.from_json(pull : JSON::PullParser) : ControlScheme?
        return if pull.read_null?

        value = JSON.parse(pull.read_raw).as_s?
        value.try { |text| Roguelike::Options.parse_control_scheme text }
      end

      def self.to_json(value : ControlScheme?, json : JSON::Builder) : Nil
        if scheme = value
          json.string scheme.to_s.underscore
        else
          json.null
        end
      end
    end

    # One preference the options screen offers.
    record Setting,
      key : String,
      section : String,
      label : String,
      help : String,
      kind : Kind,
      choices : Array({String, String}) = [] of {String, String},
      range : Range(Int32, Int32)? = nil,
      step : Int32 = 1 do
      # What sort of row the screen draws for a setting.
      enum Kind
        Toggle
        Choice
        Number
        Text
      end
    end

    # The preferences in the order the screen shows them.
    #
    # Each key is a JSON property of `Options`, except `name`, which is the
    # tester's name and is kept in `tester.json` through `Tester`.
    SETTINGS = [
      Setting.new("motion", "Display", "Motion",
        "Animate the panels. Off draws each change at once", :toggle),
      Setting.new("flicker", "Display", "Flicker",
        "Let flames waver and the camera pan. Off holds both still", :toggle),
      Setting.new("bar_color", "Display", "Bar color",
        "Whether a bar shades smoothly or steps between colors as it empties",
        :choice, [{"gradient", "Gradient"}, {"bands", "Bands"}]),
      Setting.new("mouse", "Input", "Mouse",
        "Report the mouse at the start of a run. Off lets you select text", :toggle),
      Setting.new("control_scheme", "Input", "Control scheme",
        "Choose traditional command keys or modern spatial controls", :choice,
        [{"traditional", "Traditional"}, {"modern", "Modern"}]),
      Setting.new("update_check", "Game", "Update check",
        "Say when a newer release is out, checking once a day", :toggle),
      Setting.new("autosubmit", "Game", "Send runs",
        "Send each run's replay log to the developer when the game exits", :toggle),
      Setting.new("name", "Tester", "Name",
        "The name that labels your uploaded runs", :text),
    ]

    # The options this process runs under, or `nil` when there are none.
    class_property current : Options? = nil

    property? motion : Bool = true

    property? flicker : Bool = true

    property bar_color : BarColor = BarColor::Gradient

    property? mouse : Bool = true

    @[JSON::Field(converter: Roguelike::Options::ControlSchemeValue, emit_null: true)]
    property control_scheme : ControlScheme? = nil

    property? update_check : Bool = true

    property? autosubmit : Bool = TEST_BUILD

    # The file's value of each key a flag set for this run.
    #
    # `#write` saves these in place of the flag's value, so a flag never
    # reaches the file.
    @[JSON::Field(ignore: true)]
    @overridden = {} of String => JSON::Any

    def initialize
    end

    # Where the file is under the state directory *root*.
    def self.path(root : Path) : Path
      root / FILE
    end

    # The options on file under *root*. The defaults when there is no file or
    # it does not read.
    def self.read(root : Path) : Options
      from_json File.read(path root)
    rescue File::Error | JSON::ParseException | JSON::SerializableError
      new
    end

    # The options for this run, from the file under *root* and the flags.
    #
    # Each argument is the value of a flag the person typed, or `nil` for a
    # flag they did not. A typed flag wins for this run and the file is left
    # alone.
    def self.arrange(root : Path, motion : Bool? = nil, flicker : Bool? = nil,
                     update_check : Bool? = nil, autosubmit : Bool? = nil) : Options
      options = arrange_display root, motion: motion, flicker: flicker
      options.set_flag "update_check", update_check
      options.set_flag "autosubmit", autosubmit

      options
    end

    # The display preferences for one run, from the file and any flags typed.
    # Update and upload preferences are left out for commands that do not use
    # them, such as replay viewing.
    def self.arrange_display(root : Path, motion : Bool? = nil,
                             flicker : Bool? = nil) : Options
      options = read root
      options.set_flag "motion", motion
      options.set_flag "flicker", flicker
      options
    end

    protected def set_flag(key : String, value : Bool?) : Nil
      return if value.nil?

      override key, JSON::Any.new self[key].as(Bool)
      self[key] = value
    end

    # The tester's name under *root*, which the `name` setting shows.
    def self.name(root : Path) : String
      Tester.read(root).try(&.name) || Tester::ANONYMOUS
    end

    # Renames the tester under *root*, keeping the tester id, and makes the
    # result the current tester.
    def self.rename(root : Path, name : String) : Tester
      tester = Tester.arrange(root, name: name) || Tester.named(name)
      Tester.current = tester
      tester
    end

    # What a setting holds, as the options screen shows it. A choice is the
    # value of one of its `Setting#choices`.
    alias Value = Bool | Int32 | String | ControlScheme?

    # Parses the values written by the options form and JSON file.
    def self.parse_control_scheme(value : String) : ControlScheme?
      case value
      when "traditional" then ControlScheme::Traditional
      when "modern"      then ControlScheme::Modern
      end
    end

    # The profile to use before a person has chosen one.
    def effective_control_scheme : ControlScheme
      @control_scheme || ControlScheme::Traditional
    end

    # Whether a recognized scheme is saved.
    def control_scheme_chosen? : Bool
      !@control_scheme.nil?
    end

    # What *key* holds. Raises `KeyError` for a key that is no property.
    def [](key : String) : Value
      {% for ivar in @type.instance_vars %}
        {% unless ivar.name == "overridden" %}
          if key == {{ ivar.name.stringify }}
            {% if ivar.name == "control_scheme" %}
              return @{{ ivar.name }}.try &.to_s.underscore
            {% elsif ivar.type < ::Enum %}
              return @{{ ivar.name }}.to_s.underscore
            {% else %}
              return @{{ ivar.name }}
            {% end %}
          end
        {% end %}
      {% end %}

      raise KeyError.new "no option #{key.inspect}"
    end

    # Sets what *key* holds. Raises `KeyError` for a key that is no property,
    # and `ArgumentError` for a value of the wrong kind.
    def []=(key : String, value : Value) : Value
      {% for ivar in @type.instance_vars %}
        {% unless ivar.name == "overridden" %}
          if key == {{ ivar.name.stringify }}
            {% if ivar.name == "control_scheme" %}
              if value.nil?
                @{{ ivar.name }} = nil
              elsif value.is_a?(String)
                scheme = Options.parse_control_scheme value
                raise ArgumentError.new "unknown control scheme #{value.inspect}" unless scheme
                @{{ ivar.name }} = scheme
              elsif value.is_a?(ControlScheme)
                @{{ ivar.name }} = value
              else
                raise ArgumentError.new "#{key} holds a control scheme or nil"
              end
            {% elsif ivar.type < ::Enum %}
              raise ArgumentError.new "#{key} holds a choice" unless value.is_a? String
              @{{ ivar.name }} = {{ ivar.type }}.parse value
            {% else %}
              raise ArgumentError.new "#{key} holds a #{{{ ivar.type.stringify }}}" unless value.is_a? {{ ivar.type }}
              @{{ ivar.name }} = value
            {% end %}
            return value
          end
        {% end %}
      {% end %}

      raise KeyError.new "no option #{key.inspect}"
    end

    # The flag that set *key* for this run, as it was typed, or `nil` when no
    # flag did.
    def flag(key : String) : String?
      return unless overridden? key

      held = self[key]
      "--#{held == false ? "no-" : ""}#{key.tr "_", "-"}"
    end

    # Notes that a flag set *key* for this run, and what the file held.
    protected def override(key : String, held : JSON::Any) : Nil
      @overridden[key] = held
    end

    # Whether a flag set *key* for this run.
    def overridden?(key : String) : Bool
      @overridden.has_key? key
    end

    # Makes the current value of *key* the person's own, so `#write` saves
    # it. The options screen calls this when a row changes.
    def adopt(key : String) : Nil
      @overridden.delete key
    end

    # Writes the whole file under *root*. A key a flag set holds the file's
    # value.
    def write(root : Path) : Nil
      held = JSON.parse(to_json).as_h
      @overridden.each { |key, value| held[key] = value }

      Dir.mkdir_p root
      File.write Options.path(root), "#{held.to_pretty_json}\n"
    end
  end
end
