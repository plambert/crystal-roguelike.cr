require "../../spec_helper"

Spectator.describe Roguelike::Ui::ThemeLibrary do
  alias Theme = Roguelike::Ui::Theme
  alias Library = Roguelike::Ui::ThemeLibrary

  let(root) do
    Path[File.tempname "roguelike-themes", nil].tap do |made|
      Dir.mkdir_p made
      at_exit { FileUtils.rm_rf made.to_s }
    end
  end

  let(moss) { Theme::DEFAULT.with "granite", TermBuf::Color.rgb(0x12, 0x34, 0x56) }

  describe "a file name" do
    it "comes from the name in lower case with hyphens" do
      expect(Library.file_name "My  Dark theme!").to eq "my-dark-theme.json"
      expect(Library.file_name "Paper").to eq "paper.json"
    end

    it "is nil for a name with no letter or digit" do
      expect(Library.file_name " -- ").to be_nil
      expect(Library.path root, "").to be_nil
    end
  end

  describe "a saved theme" do
    it "is written under themes and read back with its name" do
      path = Library.save root, "Moss", moss

      expect(path).to eq root / "themes" / "moss.json"
      expect(Library.read path).to eq Library::Named.new("Moss", moss)
    end

    it "writes over the file of a theme saved under the same name" do
      Library.save root, "Moss", Theme::DEFAULT
      Library.save root, "moss", moss

      expect(Library.saved root).to eq [Library::Named.new("moss", moss)]
    end

    it "refuses a name with no letter or digit" do
      expect { Library.save root, "!!", moss }.to raise_error ArgumentError
    end
  end

  describe "the list" do
    it "is empty with no directory" do
      expect(Library.saved root).to be_empty
    end

    it "orders the files by name and leaves out one that does not read" do
      Library.save root, "moss", moss
      Library.save root, "Amber", Theme::DEFAULT
      File.write Library.directory(root) / "broken.json", "oops"
      File.write Library.directory(root) / "notes.txt", "{}"

      expect(Library.saved(root).map &.name).to eq ["Amber", "moss"]
    end

    it "names a file with no name key after the file" do
      Dir.mkdir_p Library.directory(root)
      File.write Library.directory(root) / "ocean.json", %({"ground": "#001020"})

      expect(Library.saved(root).map &.name).to eq ["ocean"]
    end
  end

  describe "the built-in themes" do
    it "are Default, High contrast and Paper, in that order" do
      expect(Library::BUILT_INS.map &.name).to eq ["Default", "High contrast", "Paper"]
      expect(Library::BUILT_INS.first.theme).to eq Theme::DEFAULT
    end

    it "differ from each other" do
      expect(Library::BUILT_INS.map(&.theme).uniq!.size).to eq Library::BUILT_INS.size
    end

    it "are built only from a table that lists every color" do
      expect { Theme.built({"granite" => 0x010203}) }.to raise_error ArgumentError, /missing/
    end

    it "keep every text color at 4.5 to 1 on its background, the default aside" do
      Library::BUILT_INS.skip(1).each do |named|
        low = named.theme.readings.min_by &.[2]
        expect(low[2]).to be >= 4.5, "#{named.name}: #{low[0]} on #{low[1]} is #{low[2].round 2}"
      end
    end

    it "are found by a name that writes the same file" do
      expect(Library.built_in("PAPER").try &.name).to eq "Paper"
      expect(Library.built_in("high-contrast").try &.name).to eq "High contrast"
      expect(Library.built_in "Moss").to be_nil
    end

    it "cannot be saved over" do
      expect { Library.save root, "paper", moss }.to raise_error ArgumentError, /game's own/
    end

    it "come first in the list, then the saved themes by name" do
      Library.save root, "Moss", moss
      Library.sync root

      expect(Library.all(root).map &.name).to eq ["Default", "High contrast", "Paper", "Moss"]
    end
  end

  describe "a free name" do
    it "is the name itself when nothing has it" do
      expect(Library.unused_name root, "Moss").to eq "Moss"
    end

    it "takes the next number after a saved or a built-in name" do
      Library.save root, "Moss", moss
      Library.save root, "Moss 2", moss

      expect(Library.unused_name root, "Moss").to eq "Moss 3"
      expect(Library.unused_name root, "Paper").to eq "Paper 2"
    end
  end

  describe "the startup write" do
    it "writes each missing built-in file" do
      expect(Library.sync root).to be_nil

      Library::BUILT_INS.each do |named|
        expect(Library.read Library.directory(root) / Library.file_name(named.name).to_s).to eq Library::Named.new(named.name, named.theme)
      end
    end

    it "writes again a built-in file that differs and leaves the others" do
      Library.sync root
      paper = Library.directory(root) / "paper.json"
      File.write paper, moss.to_named_json("Paper")
      Library.save root, "Moss", moss

      expect(Library.sync root).to be_nil
      expect(File.read paper).to eq Theme::PAPER.to_named_json("Paper")
      expect(Library.read(Library.directory(root) / "moss.json").try &.theme).to eq moss
    end

    it "leaves a matching file as it is" do
      Library.sync root
      paper = Library.directory(root) / "paper.json"
      File.touch paper, Time.unix(0)

      Library.sync root
      expect(File.info(paper).modification_time).to eq Time.unix(0)
    end

    it "answers what went wrong when the directory cannot be made" do
      File.write root / "themes", "a file in the way"

      expect(Library.sync root).to contain "could not be written"
    end
  end
end
