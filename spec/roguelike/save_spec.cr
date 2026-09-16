require "../spec_helper"

Spectator.describe Roguelike::Save do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Save = Roguelike::Save

  # A store on a directory of its own, and a game to put in it.
  def store : Save::Store
    Playing.store
  end

  # The character *name* in *kept*, or a failure saying there is none.
  def held(kept : Save::Store, name : String = "Sparky") : Save::Held
    found = kept.held name
    raise "#{kept.directory} holds no character called #{name}" unless found

    found
  end

  def named(name : String, turn : Int32 = 0) : Roguelike::Game
    game = Playing.field 20, 10
    game.player.name = name
    turn.times { game.wait }
    game
  end

  describe ".slug" do
    it "keeps a plain name as it is" do
      expect(Save.slug "Sparky").to eq "Sparky"
    end

    it "keeps the case" do
      expect(Save.slug "McGee").to eq "McGee"
    end

    # A modern filesystem takes almost any byte. What this is about is a name
    # a person can type at a shell without quoting it.
    it "turns a run of anything else into one dash" do
      expect(Save.slug "Sparky the Bold").to eq "Sparky-the-Bold"
      expect(Save.slug "a/b:c").to eq "a-b-c"
      expect(Save.slug "one   two").to eq "one-two"
    end

    it "keeps letters that are not ASCII" do
      expect(Save.slug "Gúnther").to eq "Gúnther"
    end

    it "drops an emoji, because it is not a letter" do
      expect(Save.slug "Gúnther the 👹").to eq "Gúnther-the"
    end

    it "keeps a dash, an underscore and a dot" do
      expect(Save.slug "a-b_c.d").to eq "a-b_c.d"
    end

    it "takes the dashes off both ends" do
      expect(Save.slug "  !Sparky!  ").to eq "Sparky"
    end

    it "answers nothing for a name with nothing usable in it" do
      expect(Save.slug "").to eq ""
      expect(Save.slug "///").to eq ""
      expect(Save.slug "  ").to eq ""
    end

    # A file called `.` or `..` is a directory that already exists.
    it "answers nothing for a name that is a dot" do
      expect(Save.slug ".").to eq ""
      expect(Save.slug "..").to eq ""
    end

    it "cuts a name longer than a file name holds" do
      long = Save.slug "a" * 400

      expect(long.bytesize).to be <= Save::MOST_BYTES
    end
  end

  describe ".state_home" do
    it "uses XDG_STATE_HOME when it is set" do
      ENV["XDG_STATE_HOME"] = "/somewhere/state"

      expect(Save.state_home).to eq "/somewhere/state"
    ensure
      ENV.delete "XDG_STATE_HOME"
    end

    # The specification says to ignore a relative value rather than resolve
    # it against whatever directory the game happened to start in.
    it "ignores a relative XDG_STATE_HOME" do
      ENV["XDG_STATE_HOME"] = "state"

      expect(Save.state_home).to eq Path.home.join(".local", "state").to_s
    ensure
      ENV.delete "XDG_STATE_HOME"
    end

    it "falls back to ~/.local/state" do
      ENV.delete "XDG_STATE_HOME"

      expect(Save.state_home).to eq Path.home.join(".local", "state").to_s
    end
  end

  describe Save::Store do
    describe ".default" do
      it "puts the two directories under the state directory" do
        ENV["XDG_STATE_HOME"] = "/somewhere/state"

        kept = Save::Store.default
        expect(kept.directory.to_s).to eq "/somewhere/state/roguelike/saves"
        expect(kept.ended.to_s).to eq "/somewhere/state/roguelike/deaths"
      ensure
        ENV.delete "XDG_STATE_HOME"
      end
    end

    describe "#path" do
      it "names the file after the slug" do
        kept = store

        expect(kept.path("Sparky the Bold").basename)
          .to eq "Sparky-the-Bold#{Save::Store::EXTENSION}"
      end

      it "refuses a name that makes no file name" do
        kept = store

        expect { kept.path "///" }.to raise_error ArgumentError, /file name/
      end
    end

    describe "#write" do
      it "makes the directory" do
        kept = store
        kept.write named("Sparky")

        expect(Dir.exists? kept.directory).to be_true
      end

      it "writes a file named after the character" do
        kept = store
        where = kept.write named("Sparky")

        expect(File.exists? where).to be_true
        expect(where.basename).to eq "Sparky.json"
      end

      # The header is what a person reads at the top of the file, so it comes
      # before the game rather than after it.
      it "puts the header before the game" do
        kept = store
        text = File.read kept.write(named "Sparky")

        expect(text.lines.first(2).last).to contain "\"name\""
      end

      it "writes who it is, the build and how far they got" do
        kept = store
        kept.write named("Sparky", turn: 4)

        found = held kept
        expect(found.name).to eq "Sparky"
        expect(found.version).to eq Roguelike::VERSION
        expect(found.turn).to eq 4
        expect(found.level).to eq 1
        expect(found.outcome.playing?).to be_true
      end

      # A crash partway through a write must leave the last good save where
      # it was, so the new one is written beside it and renamed over it.
      it "leaves nothing behind it" do
        kept = store
        kept.write named("Sparky")

        expect(Dir.glob(kept.directory / "*.writing")).to be_empty
      end

      it "writes over a save already there" do
        kept = store
        kept.write named("Sparky")
        kept.write named("Sparky", turn: 7)

        expect(held(kept).turn).to eq 7
        expect(kept.characters.size).to eq 1
      end
    end

    describe "#read" do
      it "answers the game that was written" do
        kept = store
        kept.write named("Sparky", turn: 3)

        again = held(kept).game
        expect(again.turn).to eq 3
        expect(again.player.name).to eq "Sparky"
      end

      # A name is one character. The file it names is found however the name
      # was typed, as long as it slugs the same way.
      it "finds a character by a name that slugs the same" do
        kept = store
        kept.write named("Sparky the Bold")

        expect(kept.read "Sparky the Bold").not_to be_nil
        expect(kept.read "Sparky!the!Bold").not_to be_nil
      end

      it "answers nothing for a character it has not got" do
        expect(store.read "Nobody").to be_nil
      end

      it "answers nothing for a name that makes no file name" do
        expect(store.read "///").to be_nil
      end

      # A save from a build whose fields have moved is not worth stopping the
      # game over, and the file stays where a person can look at it.
      it "answers nothing for a file that will not parse" do
        kept = store
        Dir.mkdir_p kept.directory
        File.write kept.path("Broken"), "{ not json"

        expect(kept.read "Broken").to be_nil
        expect(File.exists? kept.path("Broken")).to be_true
      end
    end

    describe "#characters" do
      it "answers nothing for a directory that is not there" do
        expect(store.characters).to be_empty
      end

      it "answers every character in it" do
        kept = store
        kept.write named("Sparky")
        kept.write named("McGee")

        expect(kept.characters.map(&.name).sort!).to eq ["McGee", "Sparky"]
      end

      it "puts the most recently saved first" do
        kept = store
        kept.write named("Older")
        sleep 1.millisecond
        kept.write named("Newer")

        expect(kept.characters.first.name).to eq "Newer"
      end

      it "leaves out a file that will not parse" do
        kept = store
        kept.write named("Sparky")
        File.write kept.path("Broken"), "{ not json"

        expect(kept.characters.map &.name).to eq ["Sparky"]
      end
    end

    describe "#taken_by" do
      it "says nothing when there is no file" do
        expect(store.taken_by "Sparky").to be_nil
      end

      # A person carrying their own character on is not in their own way.
      it "says nothing for the character whose file it is" do
        kept = store
        kept.write named("Sparky")

        expect(kept.taken_by "Sparky").to be_nil
      end

      # Two names can make one file name. The second one would be written
      # over the first, and nobody types a new name expecting that.
      it "names the character in the way" do
        kept = store
        kept.write named("Sparky the Bold")

        expect(kept.taken_by "Sparky!the!Bold").to eq "Sparky the Bold"
      end

      # A file nobody can read is still a file a new run must not write over.
      it "names the file when the file will not parse" do
        kept = store
        Dir.mkdir_p kept.directory
        File.write kept.path("Broken"), "{ not json"

        expect(kept.taken_by "Broken").to eq "Broken"
      end

      it "says nothing for a name that makes no file name" do
        expect(store.taken_by "///").to be_nil
      end
    end

    describe "#holds?" do
      it "says whether there is a file" do
        kept = store
        expect(kept.holds? "Sparky").to be_false

        kept.write named("Sparky")
        expect(kept.holds? "Sparky").to be_true
      end

      it "says no for a name that makes no file name" do
        expect(store.holds? "///").to be_false
      end
    end

    describe "#ending" do
      it "puts the time the run ended after the slug" do
        kept = store
        at = Time.local 2026, 9, 15, 23, 45, 0

        expect(kept.ending("Sparky the Bold", at).basename)
          .to eq "Sparky-the-Bold-20260915-234500.json"
      end

      # One name can end many times, and every ending is kept.
      it "counts a second ending in the same second" do
        kept = store
        at = Time.local 2026, 9, 15, 23, 45, 0
        Dir.mkdir_p kept.ended
        File.write kept.ending("Sparky", at), "{}"

        expect(kept.ending("Sparky", at).basename)
          .to eq "Sparky-20260915-234500-2.json"
      end

      it "refuses a name that makes no file name" do
        kept = store

        expect { kept.ending "///" }.to raise_error ArgumentError, /file name/
      end
    end

    describe "#retire" do
      it "moves the file out of the saves" do
        kept = store
        kept.write named("Sparky")

        kept.retire "Sparky"

        expect(kept.holds? "Sparky").to be_false
        expect(kept.characters).to be_empty
      end

      it "answers where the file went" do
        kept = store
        kept.write named("Sparky")

        where = kept.retire "Sparky"
        raise "the file went nowhere" unless where

        expect(File.exists? where).to be_true
        expect(where.parent).to eq kept.ended
      end

      it "keeps everything the file held" do
        kept = store
        kept.write named("Sparky", turn: 6)

        kept.retire "Sparky"

        expect(kept.endings.size).to eq 1
        expect(kept.endings.first.name).to eq "Sparky"
        expect(kept.endings.first.turn).to eq 6
      end

      # The name is what a new character wants back.
      it "frees the name" do
        kept = store
        kept.write named("Sparky")
        kept.retire "Sparky"

        expect(kept.taken_by "Sparky").to be_nil
      end

      it "says nothing for a character it has not got" do
        expect(store.retire "Nobody").to be_nil
      end

      it "says nothing for a name that makes no file name" do
        expect(store.retire "///").to be_nil
      end
    end

    describe "#endings" do
      it "answers nothing for a directory that is not there" do
        expect(store.endings).to be_empty
      end

      it "answers every character whose run is over" do
        kept = store
        kept.write named("Sparky")
        kept.retire "Sparky"
        kept.write named("McGee")
        kept.retire "McGee"

        expect(kept.endings.map(&.name).sort!).to eq ["McGee", "Sparky"]
        expect(kept.characters).to be_empty
      end
    end

    describe "#remove" do
      it "takes the file away" do
        kept = store
        kept.write named("Sparky")

        expect(kept.remove "Sparky").to be_true
        expect(kept.holds? "Sparky").to be_false
      end

      it "says no for a character it has not got" do
        expect(store.remove "Nobody").to be_false
      end
    end
  end

  describe "a saved run" do
    # Everything the game holds has to survive the trip. A character carrying
    # a readied sword on a floor they have half explored is the shape of a
    # save that matters.
    it "comes back the way it went in" do
      kept = store
      game = named "Sparky", turn: 2
      game.player.inventory.add Item.new(Kind::LongSword, enchantment: 1)
      game.wield 'a'
      game.player.take_gold 40

      kept.write game
      again = held(kept).game

      expect(again.to_json).to eq game.to_json
    end
  end
end
