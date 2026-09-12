module Roguelike::Ui
  # What the character is, on one row.
  #
  # A `TermBuf::Widgets::StatusBar` cuts from the right when the row runs out
  # of width and marks the cut. So the pairs are added in the order they
  # matter: hit points first, then advancement, then the five scores, then the
  # things a person can work out for themselves.
  class StatusLine
    # What a low fraction of hit points is drawn in.
    HURT = Style::DEFAULT.fg TermBuf::Color.rgb(0xE0, 0x6C, 0x55)

    # What a dangerous fraction is drawn in.
    DYING = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0x3B, 0x30)).bold

    # Below this fraction of full health the hit points are drawn in `HURT`.
    HURT_AT = 0.5

    # Below this fraction they are drawn in `DYING`.
    DYING_AT = 0.25

    # The widget itself. A caller puts it in a tree.
    getter bar : Widgets::StatusBar

    def initialize
      @bar = Widgets::StatusBar.new
      @bar.add "hp", ""
      @bar.add "ac", ""
      @bar.add "wep", ""
      @bar.add "lv", ""
      @bar.add "xp", ""
      @bar.add "gold", ""
      @bar.add "turn", ""

      Attributes::Which.values.each { |which| @bar.add which.short.downcase, "" }

      @bar.add "at", ""
      @bar.add "mouse", "on"
    end

    # Writes whether the terminal is reporting the mouse.
    #
    # The terminal knows this. The game does not, so `Session` writes it.
    def mousing=(wanted : Bool) : Nil
      @bar.set "mouse", wanted ? "on" : "off"
    end

    # Writes what *game* holds.
    def show(game : Game) : Nil
      player = game.player

      @bar.set "hp", "#{player.hit_points}/#{player.max_hit_points}"
      @bar["hp"]?.try &.style = health player
      @bar.set "ac", player.armour_class.to_s
      @bar.set "wep", weapon game
      @bar.set "lv", player.level.to_s
      @bar.set "xp", experience player

      Attributes::Which.values.each do |which|
        @bar.set which.short.downcase, player.attributes[which].to_s
      end

      @bar.set "at", "#{player.x},#{player.y}"
      @bar.set "gold", player.gold.to_s
      @bar.set "turn", game.turn.to_s
    end

    # What the character is swinging, and what it does.
    #
    # The name has no article and no count, because neither says anything on
    # a row this narrow. Bare hands are the dice on their own, because there
    # is no name to write. `1d8+1` is the weapon's own dice with the strength
    # modifier worked in, which is what `Player#damage` answers.
    private def weapon(game : Game) : String
      held = game.player.wielded
      return game.player.damage.to_s unless held

      "#{game.lore.noun_for held} #{game.player.damage}"
    end

    # Experience, over what the next level needs.
    #
    # `25/40` is twenty five points of the forty the next level takes. The
    # last level has no next one, so it shows the count on its own.
    private def experience(player : Player) : String
      wanted = player.to_next_level
      return player.experience.to_s unless wanted

      "#{player.experience}/#{player.experience + wanted}"
    end

    # What the hit points are drawn in.
    private def health(player : Player) : Style?
      full = player.max_hit_points
      return if full <= 0

      part = player.hit_points / full
      return DYING if part <= DYING_AT
      return HURT if part <= HURT_AT

      nil
    end
  end
end
