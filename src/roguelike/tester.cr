require "json"
require "uuid"
require "./save"

module Roguelike
  # Who is playing, for the developer's dashboard.
  #
  # A tester has a name and a uuid. The name is whatever the person typed, or
  # `anonymous`. The uuid is made once and never changes, so a renamed tester
  # is still one tester. Both are kept in `tester.json` in the game's state
  # directory.
  #
  # `Tester.current` is what the upload meta and the replay header read. It is
  # `nil` until the interactive game sets it, so a headless run, the bot and
  # the specs record no tester.
  class Tester
    include JSON::Serializable

    # What the name is when nobody gave one.
    ANONYMOUS = "anonymous"

    # What the file is called.
    FILE = "tester.json"

    # The tester this process is playing as, or `nil` when there is none.
    class_property current : Tester? = nil

    getter id : String

    getter name : String

    def initialize(@id : String, @name : String)
    end

    # A tester called *name*. Blank or missing names become `anonymous`.
    #
    # *id* is kept when it is given. A new uuid is made when it is not.
    def self.named(name : String?, id : String? = nil) : Tester
      new id || UUID.random.to_s, name.try(&.strip).presence || ANONYMOUS
    end

    # Where the file is under the state directory *root*.
    def self.path(root : Path) : Path
      root / FILE
    end

    # The tester on file under *root*, or `nil` when there is none or the
    # file does not read.
    def self.read(root : Path) : Tester?
      from_json File.read(path root)
    rescue File::Error | JSON::ParseException | JSON::SerializableError
      nil
    end

    # Settles who is playing from the file and the command line.
    #
    # *id* and *name* are the values of `--tester-id` and `--tester-name`.
    # Either one rewrites the file, taking whatever it does not give from the
    # file, or from a fresh uuid and `anonymous` when there is no file. A flag
    # that repeats what the file says leaves the file alone.
    #
    # Answers `nil` when there is no file and no flag, which is when the person
    # has to be asked. Raises `ArgumentError` when *id* is not a uuid.
    def self.arrange(root : Path, id : String? = nil, name : String? = nil) : Tester?
      held = read root
      return held unless id || name

      uuid = id ? UUID.new(id).to_s : held.try(&.id) || UUID.random.to_s
      tester = new uuid, (name ? named(name).name : held.try(&.name)) || ANONYMOUS
      tester.write root unless tester == held
      tester
    end

    # Writes the file under *root*.
    def write(root : Path) : Nil
      Dir.mkdir_p root
      File.write Tester.path(root), "#{to_pretty_json}\n"
    end

    def ==(other : Tester) : Bool
      id == other.id && name == other.name
    end
  end
end
