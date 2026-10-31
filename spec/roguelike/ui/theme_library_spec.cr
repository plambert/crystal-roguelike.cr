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
end
