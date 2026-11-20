require "../../src/roguelike"

# Setters a spec uses to put hunger, thirst and the skin where it wants them.
#
# The game moves these only through `#tick`, `#eat`, `#drink`, `#quench`,
# `#slake`, `#parch` and `#refill`. A spec that needs a character a day
# hungry sets the debt rather than playing the turns.
#
# Plain methods rather than `setter`, which would declare the variables
# again without their JSON keys.
class Roguelike::Sustenance
  def hunger=(@hunger : Int32) : Int32
  end

  def thirst=(@thirst : Int32) : Int32
  end

  def water=(@water : Int32) : Int32
  end
end

# Puts a character's hunger, thirst and skin back where a new run starts.
#
# A spec that plays thousands of turns calls this between stretches, so the
# character neither weakens nor dies of something the spec is not about.
module Sustained
  def self.refresh(player : Roguelike::Player) : Nil
    sustenance = player.sustenance
    sustenance.hunger = 0
    sustenance.thirst = 0
    sustenance.water = Roguelike::Sustenance::Tuning::SKIN_UNITS
  end
end
