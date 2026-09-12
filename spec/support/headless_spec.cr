require "../spec_helper"

Spectator.describe Headless do
  alias Widgets = TermBuf::Widgets

  describe ".open" do
    it "draws nothing for a widget with nothing in it" do
      session = described_class.open Widgets::Panel.new, columns: 20, rows: 3

      expect(session.rows).to eq ["", "", ""]
    end

    it "gives back a buffer of the size asked for" do
      session = described_class.open Widgets::Panel.new, columns: 20, rows: 3

      expect(session.buffer.width).to eq 20
      expect(session.buffer.height).to eq 3
    end
  end

  describe "#render" do
    it "answers what the widgets drew" do
      root = Widgets::Panel.new
      root.add Widgets::Label.new("hello")

      session = described_class.open root, columns: 20, rows: 3

      expect(session.row(0)).to eq "hello"
    end
  end

  describe "#press" do
    it "delivers a key to the tree" do
      seen = [] of String

      root = Widgets::Panel.new
      root.add Widgets::Label.new("watching")

      session = described_class.open root, columns: 20, rows: 3
      session.app.on_event = ->(event : TermBuf::Event) do
        key = event.as? TermBuf::Events::Key
        seen << key.key.to_s if key
        nil
      end

      session.press "a"
      session.press "Ctrl+X s"

      expect(seen).to eq ["a", "Ctrl+X", "s"]
    end
  end

  describe "#resize" do
    it "lays the tree out again at the new size" do
      root = Widgets::Panel.new width: Widgets::Layout::Sizing.grow
      root.add Widgets::Label.new("x")

      session = described_class.open root, columns: 20, rows: 3
      session.render
      session.resize 40, 5

      expect(session.rows.size).to eq 5
      expect(session.app.root.rect.width).to eq 40
    end
  end
end
