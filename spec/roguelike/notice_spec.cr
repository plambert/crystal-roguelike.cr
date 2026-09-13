require "../spec_helper"

Spectator.describe Roguelike::Notice do
  alias Attributes = Roguelike::Attributes
  alias Notice = Roguelike::Notice
  alias Species = Roguelike::Species

  # A character of average stealth. The modifier is zero, so a species is
  # noticed at its own reach.
  AVERAGE = Attributes::AVERAGE

  describe ".reach" do
    it "starts at the species' own reach" do
      expect(Notice.reach Species::Goblin, AVERAGE, 0).to eq Species::Goblin.notice
    end

    it "takes squares off for stealth" do
      quiet = Notice.reach Species::Goblin, 18, 0
      loud = Notice.reach Species::Goblin, 4, 0

      expect(quiet).to eq Species::Goblin.notice - 4
      expect(loud).to eq Species::Goblin.notice + 3
    end

    it "puts squares on for light" do
      dark = Notice.reach Species::Goblin, AVERAGE, 0
      lit = Notice.reach Species::Goblin, AVERAGE, 2

      expect(lit).to eq dark + 2 * Notice::REACH_PER_LIGHT
    end

    # A carried torch lights the square its carrier stands on to seven, so a
    # goblin picks them out from three times as far off as it would in the
    # dark.
    it "notices somebody carrying a torch a long way off" do
      expect(Notice.reach Species::Goblin, AVERAGE, 7).to eq 15
      expect(Notice.reach Species::Slime, AVERAGE, 7).to eq 11
    end

    # An orc is not looking with the light, so the light says nothing about
    # how far it looks.
    it "ignores light for a species with darkvision" do
      dark = Notice.reach Species::Orc, AVERAGE, 0
      lit = Notice.reach Species::Orc, AVERAGE, 12

      expect(Species::Orc.darkvision?).to be_true
      expect(lit).to eq dark
    end

    it "never falls below arm's reach" do
      expect(Notice.reach Species::Slime, 18, 0).to be >= Notice::TOUCH
    end
  end

  describe ".touching?" do
    it "counts the eight squares around one" do
      Roguelike::Direction.values.each do |direction|
        expect(Notice.touching?({5, 5}, direction.from(5, 5))).to be_true
      end
    end

    it "counts the square itself" do
      expect(Notice.touching?({5, 5}, {5, 5})).to be_true
    end

    it "counts nothing further off" do
      expect(Notice.touching?({5, 5}, {7, 5})).to be_false
      expect(Notice.touching?({5, 5}, {7, 7})).to be_false
    end
  end

  describe ".within?" do
    # The reach is round, the way a pool of light is and the way
    # `FieldOfView` cuts a radius.
    it "measures in a straight line" do
      expect(Notice.within?({0, 0}, {4, 0}, 4)).to be_true
      expect(Notice.within?({0, 0}, {3, 2}, 4)).to be_true
      expect(Notice.within?({0, 0}, {3, 3}, 4)).to be_false
      expect(Notice.within?({0, 0}, {4, 4}, 4)).to be_false
    end
  end

  describe ".notices?" do
    it "notices nothing through a wall" do
      found = Notice.notices? Species::Orc, AVERAGE, 9, {0, 0}, {1, 0}, line: false

      expect(found).to be_false
    end

    it "notices a lit character touching it, however quiet they are" do
      found = Notice.notices? Species::Goblin, 18, 1, {5, 5}, {6, 6}

      expect(found).to be_true
    end

    # A goblin sees by the light on what it looks at. A character standing in
    # the dark is not there at all, and that is what a doused torch buys.
    it "misses an unlit character however close they stand" do
      beside = Notice.notices? Species::Goblin, AVERAGE, 0, {5, 5}, {6, 5}
      away = Notice.notices? Species::Goblin, AVERAGE, 0, {5, 5}, {7, 5}

      expect(beside).to be_false
      expect(away).to be_false
    end

    it "finds an unlit character anyway with darkvision" do
      found = Notice.notices? Species::Orc, AVERAGE, 0, {5, 5}, {11, 5}

      expect(found).to be_true
    end

    it "stops at the reach" do
      near = Notice.notices? Species::Orc, AVERAGE, 0, {0, 0}, {8, 0}
      far = Notice.notices? Species::Orc, AVERAGE, 0, {0, 0}, {9, 0}

      expect(near).to be_true
      expect(far).to be_false
    end

    it "reaches further with light on the character" do
      dim = Notice.notices? Species::Goblin, AVERAGE, 1, {0, 0}, {10, 0}
      bright = Notice.notices? Species::Goblin, AVERAGE, 7, {0, 0}, {10, 0}

      expect(dim).to be_false
      expect(bright).to be_true
    end

    it "reaches less far against a quiet character" do
      loud = Notice.notices? Species::Goblin, AVERAGE, 1, {0, 0}, {8, 0}
      quiet = Notice.notices? Species::Goblin, 18, 1, {0, 0}, {8, 0}

      expect(loud).to be_true
      expect(quiet).to be_false
    end
  end

  # The whole matrix, written out.
  #
  # Every species against every stealth against every light level, at each
  # distance. A change to any of the three rules shows as a diff rather than
  # as a spec nobody can read.
  #
  # The reach column is the raw reach. A species without darkvision reading a
  # reach of eight against a light of nothing still notices only what is
  # touching it, because it sees by the light on what it looks at.
  describe "the matrix" do
    # The stealth scores the table walks: the lowest, the average and the
    # highest a character reaches without magic.
    STEALTHS = [Attributes::MINIMUM, AVERAGE, Attributes::MAXIMUM]

    # The light levels the table walks. Nothing, a floor's own glimmer, a
    # candle at arm's length, a torch held, and a magically lit room.
    LIGHTS = [0, 1, 4, 7, 9]

    # How far off the character stands in each column.
    AWAYS = [1, 2, 4, 6, 8, 10, 14]

    def table : Array(String)
      lines = ["species stealth light reach  " + AWAYS.map { |away| "%3d" % away }.join(" ")]

      Species.values.each do |species|
        STEALTHS.each do |stealth|
          LIGHTS.each do |light|
            marks = AWAYS.map do |away|
              found = Notice.notices? species, stealth, light, {0, 0}, {away, 0}
              "  %s" % (found ? "y" : ".")
            end

            lines << "%-7s %7d %5d %5d  %s" % [
              species.label, stealth, light,
              Notice.reach(species, stealth, light), marks.join(" "),
            ]
          end
        end
      end

      lines
    end

    it "notices what it noticed last time" do
      drawn = table.join "\n"

      expect(drawn).to eq Fixture.expected("notice/matrix.txt", drawn)
    end
  end
end
