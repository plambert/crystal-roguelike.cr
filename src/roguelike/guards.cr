require "../roguelike"

module Roguelike
  class Game
    # How many ticks a guard woken by a shot moves at its launch speed.
    LAUNCH_TICKS = 5

    # What a launch adds to a guard's speed on top of a haste.
    #
    # A golem walks at about half the character's pace. Launched it moves at
    # about two and a half times that pace, which carries it across its
    # whole leash before the surge runs out.
    LAUNCH_SURGE = 140

    # How much one blow from a creature takes off a shut door.
    #
    # A wooden door holds 12, so a creature that batters breaks one in two
    # to four of its blows.
    DOOR_BLOW = Dice.new 1, 6, 2

    # What *creature* does about its post this action. Answers what that
    # cost, in energy, or `nil` to go on and chase. Always `nil` for a kind
    # that guards nothing.
    #
    # A guard chases while it is within `Kind#leash` steps of its post. One
    # step past that it gives up and walks home, and it pays nothing else
    # any heed on the way.
    private def keep_post(creature : Monster) : Int32?
      return unless creature.kind.guards?

      band = floor.band creature.band
      home = creature.home
      return unless band && home

      unless band.awareness.returning?
        return if within_leash? creature, band, home

        band.awareness = Awareness::Returning
      end

      go_home creature, band, home
    end

    # Whether *creature* stands within its leash of *home*, walking over
    # what its *band* knows of the floor and through shut doors.
    private def within_leash?(creature : Monster, band : Band, home : {Int32, Int32}) : Bool
      leash = creature.kind.leash
      walk = Descent.toward band.knowledge(floor.id), home, limit: leash + 1, doors: true
      steps = walk[creature.at]

      !steps.nil? && steps <= leash
    end

    # *creature* takes one step back toward *home*, or sleeps there. Answers
    # what that cost, in energy.
    #
    # A shut door on the way is broken down. A square someone stands on is
    # walked round when another way is as short, and waited on when not. A
    # guard that knows no way home makes the square it stands on its post.
    private def go_home(creature : Monster, band : Band, home : {Int32, Int32}) : Int32
      knowledge = band.knowledge floor.id
      walk = Descent.toward knowledge, home, doors: true
      creature.post_here unless creature.home? || walk[creature.at]

      if creature.home?
        rest_at_post band
        return Costs::TURN
      end

      ways = walk.downhill creature.x, creature.y, standing_on_squares(creature)
      direction = Descent.nearest ways, creature.at, home
      return Costs::TURN unless direction

      step_creature creature, direction.from(creature.x, creature.y)
    end

    # Puts the guard band *band* back to sleep on its post. It forgets
    # whatever it had seen, so it starts again from nothing when it wakes.
    private def rest_at_post(band : Band) : Nil
      knowledge = band.knowledge floor.id
      knowledge.sightings.keys.each { |who| knowledge.lost who }
      band.awareness = Awareness::Asleep
    end

    # The guard in *band*. `nil` for a band with none.
    private def guard_of(band : Band) : Monster?
      floor.each_monster do |_column, _row, creature|
        return creature if creature.band == band.id && creature.kind.guards?
      end
    end

    # Whether *creature* gets past a shut door, by opening it or breaking it.
    private def passes_doors?(creature : Monster) : Bool
      creature.kind.opens_doors? || creature.kind.batters?
    end

    # *creature* steps onto *wanted*, or swings at the shut door there when
    # its kind breaks doors down. Answers what that cost, in energy.
    private def step_creature(creature : Monster, wanted : {Int32, Int32}) : Int32
      if creature.kind.batters? && shut_door?(wanted)
        creature_batters creature, wanted
        return creature.swing
      end

      walk_creature creature, wanted
      creature.stride
    end

    # *creature* swings at the shut door on *spot*.
    #
    # It rolls `DOOR_BLOW`, with no roll to hit. The blow is heard the way
    # the character's own is. The character is told when they can see the
    # door, and the creature is named when they can see it as well.
    private def creature_batters(creature : Monster, spot : {Int32, Int32}) : Nil
      damage = Combat.damage exchange, DOOR_BLOW
      left = floor.batter spot[0], spot[1], damage
      make_noise Noise::Sound.new(spot, :door_struck, creature: creature)

      seen = can_see? spot[0], spot[1]
      named = can_see_creature? creature.x, creature.y
      by = named ? creature.id : nil
      unseen = !named

      if left.zero?
        record Event::DoorStruck.new(spot, damage, by, unseen) if seen
        break_door spot, creature
      elsif seen
        line = named ? "The #{creature.label} #{creature.kind.verb} the door." : "Something pounds on the door."
        say line, Event::DoorStruck.new(spot, damage, by, unseen)
      end
    end

    # Breaks in the door on *spot*, struck by *creature*.
    #
    # The band of *creature* writes the doorway down as it now is.
    private def break_door(spot : {Int32, Int32}, creature : Monster) : Nil
      seen = can_see? spot[0], spot[1]
      named = can_see_creature? creature.x, creature.y
      fell_door spot

      floor.band(creature.band).try &.knowledge(floor.id).touch(floor, spot[0], spot[1], @turn)
      make_noise Noise::Sound.new(spot, :door_broken, creature: creature)
      return unless seen

      say "The door breaks!", Event::DoorBroken.new(spot, named ? creature.id : nil, !named)
    end

    # *creature*, a guard just woken by a shot, throws itself at the
    # character.
    #
    # It goes at its own speed, plus a haste, plus `LAUNCH_SURGE`, for
    # `LAUNCH_TICKS`. The character is told it is coming whether or not they
    # can see it, because they hear something that heavy move that fast.
    private def launch(creature : Monster) : Nil
      creature.pace.launch LAUNCH_TICKS, LAUNCH_SURGE

      unless can_see_creature? creature.x, creature.y
        return say "Something heavy comes at you with surprising speed.", Event::Launched.new
      end

      say "The #{creature.label} launches itself at you with surprising speed.",
        Event::Launched.new(creature.id, creature.label)
    end
  end
end
