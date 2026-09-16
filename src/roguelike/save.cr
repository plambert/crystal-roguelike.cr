require "json"

module Roguelike
  # Saved characters on disk.
  #
  # One character is one file: the whole `Game` written as JSON, under a
  # header saying who it is, which build wrote it, when, and how far they
  # have got. The header is first in the file, so `head` on one says who it
  # belongs to without reading the rest.
  #
  # Nothing here is a secret and nothing here is checked. A person who wants
  # to edit their character opens the file and edits it. The format is meant
  # to be read.
  module Save
    # What one file holds.
    #
    # The header fields are declared before the game, so they are written
    # before it. `Player#name` is what the character is called; `#name` here
    # repeats it so that the file says whose it is without parsing the game.
    class Held
      include JSON::Serializable

      # What the person called the character, as they typed it.
      getter name : String

      # Which build wrote the file.
      getter version : String

      # When it was written.
      getter saved : Time

      # How many turns had been taken.
      getter turn : Int32

      # What level the character had reached.
      getter level : Int32

      # How the run stood. `Playing` for one still going.
      getter outcome : Outcome

      # The run.
      getter game : Game

      def initialize(@name : String, @version : String, @saved : Time,
                     @turn : Int32, @level : Int32, @outcome : Outcome,
                     @game : Game)
      end

      # What *game* is written out as, now.
      def self.of(game : Game) : Held
        new game.player.name, VERSION, Time.utc, game.turn,
          game.player.level, game.outcome, game
      end
    end

    # What a name is called on disk.
    #
    # A modern filesystem takes almost any name, so this is not about what a
    # filesystem allows. It is about what a person can type at a shell without
    # quoting, and what cannot be mistaken for a path. A letter, a digit, a
    # dash, an underscore and a dot survive; every other character becomes one
    # dash, and a run of dashes becomes one.
    #
    # Letters keep their case and keep their accents, so "Gúnther the Bold"
    # is `Gúnther-the-Bold`. Two names that differ only in case share a file
    # on a filesystem that ignores case, which is most of them on this
    # platform.
    #
    # Answers an empty string for a name with nothing usable in it. A caller
    # refuses that rather than writing a file called nothing.
    def self.slug(name : String) : String
      kept = String.build do |made|
        name.strip.each_char do |char|
          made << (usable?(char) ? char : '-')
        end
      end

      kept = kept.gsub(/-+/, '-').strip '-'
      return "" if kept.empty? || kept == "." || kept == ".."

      kept.byte_slice 0, Math.min(kept.bytesize, MOST_BYTES)
    end

    # The most bytes a file name takes, leaving room for the extension.
    #
    # Most filesystems stop at 255 bytes. This is well inside that, and long
    # enough for any name a person types.
    MOST_BYTES = 96

    # Whether *char* goes into a file name as itself.
    private def self.usable?(char : Char) : Bool
      char.letter? || char.number? || char == '-' || char == '_' || char == '.'
    end

    # Three directories of characters: the ones still being played, the ones
    # who died, and the ones who came out alive.
    #
    # A caller holds one of these. Nothing in the game reaches for the default
    # directories on its own, so a spec drives a store on a temporary
    # directory and a run drives the one under the person's home.
    class Store
      # Where a character still being played is written.
      getter directory : Path

      # Where a character who died goes.
      getter deaths : Path

      # Where a character who came out alive goes.
      getter wins : Path

      # What one file is called, after the character's slug.
      EXTENSION = ".json"

      # What the three directories are called under the game's own.
      SAVES  = "saves"
      DEATHS = "deaths"
      WINS   = "wins"

      def initialize(@directory : Path, @deaths : Path, @wins : Path)
      end

      # The store this game saves to, under the XDG state directory.
      #
      # `$XDG_STATE_HOME/roguelike` when that is set and absolute, and
      # `~/.local/state/roguelike` when it is not. That is what the XDG base
      # directory specification says to do.
      def self.default : Store
        under Path[Save.state_home] / "roguelike"
      end

      # A store on the three directories under *root*.
      def self.under(root : Path) : Store
        new root / SAVES, root / DEATHS, root / WINS
      end

      # Where a run that ended with *outcome* is kept.
      #
      # A character who died goes among the deaths. Everyone else goes among
      # the wins. A character who climbed down and out won, and one who
      # climbed back out the way they came in is alive, which is the thing the
      # two directories tell apart.
      def ended(outcome : Outcome) : Path
        outcome.died? ? @deaths : @wins
      end

      # Where the character called *name* is written.
      def path(name : String) : Path
        slug = Save.slug name
        raise ArgumentError.new "#{name.inspect} makes no file name" if slug.empty?

        @directory / "#{slug}#{EXTENSION}"
      end

      # Whether there is a file for *name*.
      def holds?(name : String) : Bool
        File.exists? path(name)
      rescue ArgumentError
        false
      end

      # Writes *game*. Answers where it went.
      #
      # The file is written beside itself and renamed over the old one, so a
      # crash partway through leaves the last good save where it was rather
      # than half of a new one.
      def write(game : Game) : Path
        wanted = path game.player.name
        Dir.mkdir_p @directory

        temporary = Path["#{wanted}.writing"]
        File.write temporary, Held.of(game).to_pretty_json
        File.rename temporary, wanted

        wanted
      end

      # Who already has the file that *name* would be written to.
      #
      # Answers `nil` when there is no file, and `nil` when the file belongs
      # to a character called exactly *name*. That character is the person
      # carrying on rather than somebody in the way.
      #
      # Answers a name otherwise: the character's own when the file parses,
      # and the file's own when it does not. A file nobody can read is still
      # a file a new run must not write over.
      def taken_by(name : String) : String?
        found = path name
        return unless File.exists? found

        whose = held name
        return if whose && whose.name == name

        whose.try(&.name) || found.basename(EXTENSION)
      rescue ArgumentError
        nil
      end

      # The character called *name*, or `nil` for one this store has not got.
      #
      # A file that will not parse answers `nil` as well. A save from a build
      # whose fields have moved is not worth stopping the game over, and the
      # file is left where it is for a person to look at.
      def read(name : String) : Game?
        held(name).try &.game
      end

      # :ditto:
      def held(name : String) : Held?
        found = path name
        return unless File.exists? found

        Held.from_json File.read(found)
      rescue ArgumentError | JSON::ParseException | IO::Error
        nil
      end

      # Every character in the store, the most recently written first.
      #
      # The order comes from when each file was last written rather than from
      # the `saved` field in it. The field is written to the second and two
      # saves can land in the same one; the filesystem counts smaller.
      #
      # A file that will not parse is left out. The list is what a person is
      # offered, and offering a file that cannot be loaded helps nobody.
      def characters : Array(Held)
        listed @directory
      end

      # Every character in *where*, the most recently written first.
      private def listed(where : Path) : Array(Held)
        return [] of Held unless Dir.exists? where

        found = Dir.glob where / "*#{EXTENSION}"
        found.sort_by! { |name| -File.info(name).modification_time.to_unix_ms }

        found.compact_map { |name| Held.from_json File.read(name) rescue nil }
      end

      # Takes the character called *name* out of the store.
      def remove(name : String) : Bool
        File.delete? path(name)
      rescue ArgumentError
        false
      end

      # Takes the character called *name* out of the saves and puts them where
      # a run that ended with *outcome* goes. Answers where they went, or
      # `nil` when there was no file.
      #
      # The name is free afterwards. A person whose character died starts
      # again under the same name, and the run that ended is still on disk for
      # them to read.
      def retire(name : String, outcome : Outcome,
                 at : Time = Time.local) : Path?
        from = path name
        return unless File.exists? from

        where = ended outcome
        Dir.mkdir_p where
        wanted = ending name, outcome, at
        File.rename from, wanted

        wanted
      rescue ArgumentError
        nil
      end

      # What a retired character's file is called.
      #
      # The slug with the time the run ended after it, so one name can end
      # many times and every ending is kept. A second ending in the same
      # second takes a count as well.
      def ending(name : String, outcome : Outcome,
                 at : Time = Time.local) : Path
        slug = Save.slug name
        raise ArgumentError.new "#{name.inspect} makes no file name" if slug.empty?

        where = ended outcome
        stamp = at.to_s "%Y%m%d-%H%M%S"
        wanted = where / "#{slug}-#{stamp}#{EXTENSION}"

        count = 2
        while File.exists? wanted
          wanted = where / "#{slug}-#{stamp}-#{count}#{EXTENSION}"
          count += 1
        end

        wanted
      end

      # Every character who died, the most recently written first.
      def died : Array(Held)
        listed @deaths
      end

      # Every character who came out alive, the most recently written first.
      def won : Array(Held)
        listed @wins
      end
    end

    # Where state files go, as the XDG base directory specification says.
    #
    # `$XDG_STATE_HOME` when it is set and absolute. A relative value is
    # ignored, which is what the specification asks for.
    def self.state_home : String
      held = ENV["XDG_STATE_HOME"]?
      return held if held && held.starts_with? '/'

      Path.home.join(".local", "state").to_s
    end
  end
end
