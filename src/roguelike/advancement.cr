module Roguelike
  # How a character grows.
  #
  # Two tables and nothing else. Hit points come from constitution and level.
  # Experience levels come from a doubling threshold. Both are arithmetic
  # rather than a roll, so a character of a given level and constitution
  # always has the same maximum.
  module Advancement
    # The highest level a character reaches.
    #
    # The threshold doubles at every level, so the number at level 20 is five
    # million. Anything past that is a number nobody reads.
    MAX_LEVEL = 20

    # Hit points at level one, before constitution.
    BASE_HIT_POINTS = 8

    # Hit points added by each level after the first, before constitution.
    HIT_POINTS_PER_LEVEL = 4

    # Experience needed to reach level two.
    FIRST_THRESHOLD = 20

    # Maximum hit points for a character of *level* with *constitution*.
    #
    # Constitution counts once per level. A tough character pulls further
    # ahead as they grow, which is what makes constitution worth having.
    def self.max_hit_points(level : Int32, constitution : Int32) : Int32
      held = level.clamp 1, MAX_LEVEL
      bonus = Attributes.modifier(constitution) * held

      Math.max BASE_HIT_POINTS + (held - 1) * HIT_POINTS_PER_LEVEL + bonus, 1
    end

    # Experience needed to reach *level*.
    #
    # Zero at level one, which is where a character starts. It doubles at
    # every level after that.
    def self.threshold(level : Int32) : Int32
      return 0 if level <= 1
      return threshold(MAX_LEVEL) if level > MAX_LEVEL

      FIRST_THRESHOLD << (level - 2)
    end

    # The level *experience* points reach.
    def self.level_for(experience : Int32) : Int32
      level = 1

      while level < MAX_LEVEL && experience >= threshold(level + 1)
        level += 1
      end

      level
    end

    # Experience still needed to reach the next level. `nil` at `MAX_LEVEL`.
    def self.to_next(experience : Int32) : Int32?
      level = level_for experience
      return if level >= MAX_LEVEL

      threshold(level + 1) - experience
    end
  end
end
