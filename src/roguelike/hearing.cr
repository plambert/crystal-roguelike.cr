require "../roguelike"

module Roguelike
  class Game
    # How far the character's noise carried at its last peak, and the turn
    # it peaked on. `#noise` reads the two. Neither is written out, so a run
    # loaded from a save starts quiet.
    @[JSON::Field(ignore: true)]
    @noise_peak : Int32 = 0

    @[JSON::Field(ignore: true)]
    @noise_turn : Int32 = 0

    # Where the sounds the character made in the last action went.
    #
    # `#perform` empties it first. The map draws it until the next action.
    @[JSON::Field(ignore: true)]
    getter echoes : Array(Noise::Echo) = [] of Noise::Echo

    # The sounds out of sight the character heard in the last action.
    #
    # `#perform` empties it first. The map marks each one until the next
    # action.
    @[JSON::Field(ignore: true)]
    getter overheard : Array(Noise::Heard) = [] of Noise::Heard

    # The turn each stirring band began to stir, by band id. A band missing
    # from it, as after a save is loaded, searches on the next tick.
    @[JSON::Field(ignore: true)]
    @stirred : Hash(String, Int32) = {} of String => Int32

    # The turn the character was last told of each sort of sound.
    @[JSON::Field(ignore: true)]
    @heard_turn : Hash(Noise::Source, Int32) = {} of Noise::Source => Int32

    # How far the character's recent noise carries, in squares.
    #
    # Under `Noise::Decay::Fall` it rises to how far each sound the
    # character makes got, and falls `Noise::FADE` squares a turn after
    # that. Under `Noise::Decay::LastAction` it is how far the loudest sound
    # of the last action got.
    def noise : Int32
      case Noise::DECAY
      in .fall?
        falling
      in .last_action?
        @echoes.max_of?(&.carried) || 0
      end
    end

    # Makes *sound* on the floor the character is on.
    #
    # Every band with a member the sound reaches hears it. A band asleep
    # wakes and searches. A band awake writes down where the sound came
    # from and goes to look. What it writes down is where the character is
    # believed to be, and where the creature that made the sound is when the
    # band is hostile to it.
    #
    # A sound the character made raises `#noise` and goes on `#echoes`. One
    # a creature made, which reaches the character from out of sight, may be
    # told to them.
    private def make_noise(sound : Noise::Sound) : Nil
      reach = Noise.spread floor, sound.at, sound.loudness
      bands_hear sound, reach

      if sound.characters?
        echo = Noise::Echo.new sound.at, sound.loudness, reach
        @echoes << echo
        carried = echo.carried
        if carried >= falling
          @noise_peak = carried
          @noise_turn = @turn
        end
      else
        overheard sound, reach
      end
    end

    # What `#noise` reads under `Noise::Decay::Fall`.
    private def falling : Int32
      Math.max @noise_peak - Math.max(@turn - @noise_turn - 1, 0) * Noise::FADE, 0
    end

    # Lets every band with a member *reach* holds hear *sound*.
    private def bands_hear(sound : Noise::Sound, reach : Descent) : Nil
      heard = {} of String => Monster
      floor.each_monster do |column, row, creature|
        next if creature.same? sound.creature
        next unless Noise.hears? reach, {column, row}

        heard[creature.band] ||= creature
      end

      maker = sound.creature
      heard.each do |id, member|
        band = floor.band id
        next unless band

        knowledge = band.knowledge floor.id
        learned = false

        believed = sound.character
        if believed
          learned = true
          hear knowledge, Knowledge::PLAYER, believed
        end

        if maker && hostile_to?(band, maker)
          learned = true
          hear knowledge, Knowledge.creature(maker.id), maker.at
        end

        stir band, member if learned && band.awareness.asleep?
      end
    end

    # Starts *band* waking, from a sound *member* heard.
    #
    # It takes no step until the turn after, and then searches toward what it
    # heard. A member the character can see is said to stir.
    private def stir(band : Band, member : Monster) : Nil
      band.awareness = Awareness::Stirring
      @stirred[band.id] = @turn
      return unless can_see_creature? member.x, member.y

      say "The #{member.label} stirs.", Event::Stirred.new(member.id, member.label)
    end

    # Every band that began stirring on an earlier turn starts searching.
    #
    # A band that hears something during a tick stirs through the rest of
    # it and the whole tick after, so it always stands still for one turn.
    private def creatures_stir : Nil
      floor.each_band do |band|
        next unless band.awareness.stirring?

        began = @stirred[band.id]?
        next if began && began >= @turn

        @stirred.delete band.id
        band.awareness = Awareness::Alert
      end
    end

    # Writes into *knowledge* that *who* is at *spot*, from a sound.
    #
    # What was seen this turn is newer than what was heard, so a band that
    # can see *who* goes on believing its eyes.
    private def hear(knowledge : Knowledge, who : String, spot : {Int32, Int32}) : Nil
      return if knowledge.sighting(who).try(&.turn) == @turn

      knowledge.saw who, spot[0], spot[1], @turn
    end

    # Whether *band* fights *creature*.
    private def hostile_to?(band : Band, creature : Monster) : Bool
      theirs = floor.band creature.band
      !theirs.nil? && band.hostile?(theirs)
    end

    # Tells the character of *sound*, made by a creature, when it reaches
    # them and they cannot see where it came from.
    #
    # One line for each sort of sound in `Noise::QUIET` turns, so a fight
    # out of sight is one line and not one a swing.
    private def overheard(sound : Noise::Sound, reach : Descent) : Nil
      return unless sound.character.nil?
      return unless Noise.hears? reach, @player.at

      seen = sight
      return if seen.includes? sound.at[0], sound.at[1]

      @overheard << Noise::Heard.new(edge(seen, sound.at), sound.source)

      last = @heard_turn[sound.source]?
      return if last && @turn - last < Noise::QUIET

      @heard_turn[sound.source] = @turn
      way = Pursuit.straight(@player.at, sound.at).try &.label
      line = way ? "You hear #{sound.source.heard} to the #{way}." : "You hear #{sound.source.heard}."
      say line, Event::Heard.new(sound.source.label, way)
    end

    # The last square in sight on the line from the character toward *at*.
    # The square one step along when nothing past the character is in sight.
    private def edge(seen : Vision, at : {Int32, Int32}) : {Int32, Int32}
      here = @player.at
      found = Line.step(here, at) || here
      Line.walk(here, at) do |spot|
        next if spot == here
        break unless seen.includes? spot[0], spot[1]

        found = spot
      end
      found
    end
  end
end
