require "../../src/roguelike"

# Setters a spec uses to put hunger, thirst and the skin where it wants them.
#
# The game moves these only through `#tick`, `#eat`, `#drink`, `#quench` and
# `#refill`. A spec that needs a character three thousand turns hungry sets
# the counter rather than playing the turns.
class Roguelike::Sustenance
  setter hunger : Int32
  setter thirst : Int32
  setter water : Int32
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
    sustenance.water = Roguelike::Sustenance::WATER_MAX
  end
end
