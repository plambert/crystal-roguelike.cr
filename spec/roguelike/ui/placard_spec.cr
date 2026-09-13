require "../../spec_helper"

Spectator.describe Roguelike::Ui::Placard do
  alias Placard = Roguelike::Ui::Placard

  # A placard in a tree of its own, with no game behind it.
  #
  # The widget decides nothing about a run. A spec about the box itself needs
  # no floor, no character and no keys bound.
  class Stand
    getter placard : Placard
    getter session : Headless::Session
    getter answered : Array(Char?) = [] of Char?

    def initialize(columns : Int32 = 60, rows : Int32 = 20)
      @placard = Placard.new
      root = TermBuf::Widgets::Panel.new(
        width: TermBuf::Widgets::Layout::Sizing.grow,
        height: TermBuf::Widgets::Layout::Sizing.grow)

      @session = Headless.open root, columns, rows
      @placard.on_answer = ->(key : Char?) { @answered << key; nil }
    end

    def show(title : String = "A heading",
             lines : Array(String) = ["one", "two"],
             keys : String = "yn",
             default : Char? = 'n',
             footer : String = "Really?") : Nil
      @placard.show @session.app, title, lines, keys, default, footer
      @session.render
    end

    def press(description : String) : Nil
      @session.press description
      @session.render
    end

    def text : String
      @session.text
    end
  end

  describe "#show" do
    it "puts the lines on it" do
      stand = Stand.new
      stand.show lines: ["one", "two", "three"]

      expect(stand.placard.lines).to eq ["one", "two", "three"]
      expect(stand.placard.offered.text).to eq "Really?  [yN]"
    end

    it "heads it with the title" do
      stand = Stand.new
      stand.show title: "You died"

      expect(stand.placard.heading).to eq "You died"
      expect(stand.text).to contain "You died"
    end

    it "draws the lines" do
      stand = Stand.new
      stand.show lines: ["turn 41", "level 3"]

      expect(stand.text).to contain "turn 41"
      expect(stand.text).to contain "level 3"
    end

    it "marks the default key upper case" do
      stand = Stand.new
      stand.show keys: "yn", default: 'y'

      expect(stand.placard.offering).to eq "[Yn]"
    end

    it "offers the keys as they are when there is no default" do
      stand = Stand.new
      stand.show keys: "pq", default: nil

      expect(stand.placard.offering).to eq "[pq]"
    end

    it "refuses a default that is not one of the keys" do
      stand = Stand.new

      expect { stand.show keys: "yn", default: 'z' }.to raise_error ArgumentError
    end
  end

  describe "answering" do
    it "answers with the key that was pressed" do
      stand = Stand.new
      stand.show

      stand.press "y"

      expect(stand.answered).to eq ['y']
      expect(stand.placard.showing?).to be_false
    end

    it "answers with the default on Enter" do
      stand = Stand.new
      stand.show default: 'n'

      stand.press "Enter"

      expect(stand.answered).to eq ['n']
    end

    it "answers with nothing on Escape" do
      stand = Stand.new
      stand.show

      stand.press "Escape"

      expect(stand.answered).to eq [nil]
    end

    # A key outside the set reaches the box and stops there. The box is
    # modal, so nothing behind it answers.
    it "stays up on a key it does not offer" do
      stand = Stand.new
      stand.show keys: "yn"

      stand.press "z"

      expect(stand.answered).to be_empty
      expect(stand.placard.showing?).to be_true
    end

    # A closed box that kept its bindings would answer again on the next
    # press of the same key.
    it "answers once" do
      stand = Stand.new
      stand.show

      stand.press "y"
      stand.press "y"

      expect(stand.answered).to eq ['y']
    end
  end

  describe "a long list" do
    it "cuts it and says how much was left out" do
      stand = Stand.new
      stand.show lines: (1..(Placard::MOST_LINES + 10)).map &.to_s

      expect(stand.placard.lines.size).to eq Placard::MOST_LINES
      expect(stand.placard.lines.last).to eq "and 11 more"
    end
  end
end
