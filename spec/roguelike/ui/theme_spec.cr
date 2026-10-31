require "../../spec_helper"

Spectator.describe Roguelike::Ui::Theme do
  alias Theme = Roguelike::Ui::Theme

  # A state directory of its own. The specs never touch the real one.
  let(root) do
    Path[File.tempname "roguelike-theme", nil].tap do |made|
      Dir.mkdir_p made
      at_exit { FileUtils.rm_rf made.to_s }
    end
  end

  describe "the file" do
    it "reads back what the default writes" do
      expect(Theme.from_json Theme::DEFAULT.to_json).to eq Theme::DEFAULT
    end

    it "writes and reads back a changed theme" do
      changed = Theme::DEFAULT.with "granite", TermBuf::Color.rgb(0x12, 0x34, 0x56)
      changed.write root

      expect(Theme.read root).to eq changed
    end

    it "writes one color on each line" do
      Theme::DEFAULT.write root
      lines = File.read_lines(Theme.path root)

      expect(lines.size).to eq Theme.keys.size + 2
    end

    it "keeps the default for a key the file leaves out" do
      File.write Theme.path(root), %({"granite": "#010203"})
      read = Theme.read root

      expect(read.granite).to eq TermBuf::Color.rgb(1, 2, 3)
      expect(read.sandstone).to eq Theme::DEFAULT.sandstone
      expect(read.with "granite", Theme::DEFAULT.granite).to eq Theme::DEFAULT
    end

    it "answers the default when there is no file" do
      expect(Theme.read root).to eq Theme::DEFAULT
    end

    it "answers the default for a file that is not JSON" do
      File.write Theme.path(root), "oops"

      expect(Theme.read root).to eq Theme::DEFAULT
    end

    it "answers the default for a color that is not #rrggbb" do
      File.write Theme.path(root), %({"granite": "grey"})

      expect(Theme.read root).to eq Theme::DEFAULT
    end

    it "answers the default for a color that is not a string" do
      File.write Theme.path(root), %({"granite": 12})

      expect(Theme.read root).to eq Theme::DEFAULT
    end
  end

  describe "a name" do
    it "writes the name first and reads it back" do
      changed = Theme::DEFAULT.with "granite", TermBuf::Color.rgb(0x12, 0x34, 0x56)
      changed.write root, "Moss"

      expect(File.read_lines(Theme.path root)[1]).to eq %(  "name": "Moss",)
      expect(Theme.load root).to eq({changed, "Moss"})
    end

    it "reads a file with no name as a theme with no name" do
      File.write Theme.path(root), %({"granite": "#010203"})

      expect(Theme.load(root)[1]).to be_nil
      expect(Theme.read(root).granite).to eq TermBuf::Color.rgb(1, 2, 3)
    end

    it "writes the same text with no name as the plain JSON" do
      expect(Theme::DEFAULT.to_named_json).to eq "#{Theme::DEFAULT.to_pretty_json}\n"
    end
  end

  describe "reading pasted text" do
    it "takes the colors and the name" do
      theme, name = Theme.parse %({"name": " Moss ", "granite": "#010203"})

      expect(name).to eq "Moss"
      expect(theme).to eq Theme::DEFAULT.with("granite", TermBuf::Color.rgb(1, 2, 3))
    end

    it "takes text with its line breaks flattened" do
      text = Theme::DEFAULT.with("hero", TermBuf::Color.rgb(9, 9, 9)).to_named_json("Moss").gsub('\n', ' ')

      expect(Theme.parse(text)[0].hero).to eq TermBuf::Color.rgb(9, 9, 9)
    end

    it "ignores a key that is not a color" do
      theme, name = Theme.parse %({"granite": "#010203", "sparkle": "#ffffff", "version": 2})

      expect(name).to be_nil
      expect(theme.granite).to eq TermBuf::Color.rgb(1, 2, 3)
    end

    it "names every bad color and keeps none of the colors" do
      expect { Theme.parse %({"granite": "#010203", "hero": "white", "ground": 12}) }
        .to raise_error(Theme::Unreadable, "These colors are not #rrggbb: hero, ground.")
    end

    it "refuses text that is not JSON" do
      expect { Theme.parse %({"granite": ) }.to raise_error(Theme::Unreadable, /not JSON/)
    end

    it "refuses JSON that is not an object" do
      expect { Theme.parse %(["#010203"]) }.to raise_error(Theme::Unreadable, "This is not a JSON object.")
    end
  end

  describe "#rrggbb" do
    it "writes a color in lower case" do
      expect(Theme::Hex.to_hex TermBuf::Color.rgb(0xA0, 0x0B, 0xFF)).to eq "#a00bff"
      expect(Theme::DEFAULT.to_json).to contain %("granite":"#a0a6b2")
    end

    it "reads either case" do
      expect(Theme.from_json(%({"red": "#A00BFF"})).red).to eq TermBuf::Color.rgb(0xA0, 0x0B, 0xFF)
      expect(Theme.from_json(%({"red": "#a00bff"})).red).to eq TermBuf::Color.rgb(0xA0, 0x0B, 0xFF)
    end

    it "refuses a short or long form" do
      expect { Theme.from_json %({"red": "#abc"}) }.to raise_error JSON::ParseException
      expect { Theme.from_json %({"red": "#a00bff00"}) }.to raise_error JSON::ParseException
      expect { Theme.from_json %({"red": "a00bff"}) }.to raise_error JSON::ParseException
    end
  end

  describe "the entries" do
    it "lists every color once" do
      keys = Theme::ENTRIES.map(&.key)

      expect(keys.sort).to eq Theme.keys.sort!
      expect(keys.uniq.size).to eq keys.size
    end

    it "names each color for its row" do
      Theme::ENTRIES.each do |entry|
        expect(entry.label).not_to be_empty
        expect(Theme::DEFAULT[entry.key]).to be_a TermBuf::Color
      end
    end

    it "keeps each group together" do
      groups = Theme::ENTRIES.map(&.group)

      expect(groups.chunks(&.itself).map(&.first)).to eq groups.uniq
      expect(groups.uniq).to eq %w[Map Creatures Light Items Text Panels Bars]
    end

    it "refuses a key that is not a color" do
      expect { Theme::DEFAULT["nothing"] }.to raise_error KeyError
      expect { Theme::DEFAULT.with "nothing", TermBuf::Color.rgb(0) }.to raise_error KeyError
    end
  end

  describe "the theme in use" do
    it "is the default" do
      expect(Theme.current).to eq Theme::DEFAULT
    end
  end
end
