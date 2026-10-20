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
