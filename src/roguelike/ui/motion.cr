module Roguelike::Ui
  # Whether the panels animate.
  #
  # Every animation of the panels asks `.on?` before it arms a timer. With
  # motion off it draws its end state at once, in one frame. `--no-motion`
  # turns it off, and so does the debug console's `motion off`. The specs
  # turn it off, so a screen fixture is the same on every run.
  #
  # The flames, the camera pan and the other timers the map runs do not ask.
  module Motion
    @@on = true

    # Whether animations run.
    def self.on? : Bool
      @@on
    end

    # Turns animations on or off. Answers *on*.
    def self.on=(on : Bool) : Bool
      @@on = on
    end
  end
end
