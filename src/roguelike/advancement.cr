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
    # The threshold doubles at every level, so the number at level 20 is
    # five million.
    MAX_LEVEL = 20

    # Hit points at level one, before constitution.
    #
    # A character of average constitution has to survive a fight with the
    # commonest creature on the floor. At eight they did not: a goblin took
    # them down in under four turns and needed six to fall, so every fight at
    # level one was a loss and there was no way to reach level two.
    BASE_HIT_POINTS = 12

    # Hit points added by each level after the first, before constitution.
    HIT_POINTS_PER_LEVEL = 4

    # Experience needed to reach level two.
    FIRST_THRESHOLD = 20

    # Ticks one hit point of regeneration takes at average constitution.
    REGENERATION = 20

    # Ticks taken off that by each point of the constitution modifier.
    #
    # The modifier runs from four under to four over, so the rate runs from
    # a point every eight ticks at a constitution of eighteen to a point
    # every thirty-two at three.
    REGENERATION_PER_POINT = 3

    # The fastest anything regenerates, however tough it is.
    REGENERATION_LEAST = 5

    # Ticks one hit point of regeneration takes at *constitution*.
    #
    # Constitution already decides how many hit points there are. This is the
    # other half of the same idea: a tough character has more hit points and
    # regenerates them faster.
    def self.regeneration(constitution : Int32) : Int32
      found = REGENERATION -
              Attributes.modifier(constitution) * REGENERATION_PER_POINT

      Math.max found, REGENERATION_LEAST
    end

    # Maximum hit points for a character of *level* with *constitution*.
    #
    # Constitution counts once per level, so a tough character pulls further
    # ahead as they grow.
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
