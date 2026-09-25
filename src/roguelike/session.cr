require "termbuf"
require "./ui"

module Roguelike
  # One run, from taking the terminal over to giving it back.
  #
  # This is the only class in the game that owns a device. `Ui::Play` owns
  # everything shown and everything the keys do. `Ui::Play` owns no device, so
  # specs drive it over a buffer. What is left here is the frame loop, the
  # mouse and the cursor.
  class Session
    # Runs games on the terminal until nobody asks for another. Gives the
    # terminal back however the last one ends. That includes an exception and
    # a signal. The block form of `Terminal.open` does that.
    #
    # Answers the session that ran last, which is what the caller reports on.
    # Answers `nil` when the window is too small to play in. It writes the
    # reason to stderr in that case. It does not take the terminal over at
    # all.
    #
    # *seed* is the run's seed, or `nil` for a fresh one. A person who asks
    # for another run gets the same seed when one was named and a fresh seed
    # when none was, so `--seed N` goes on reproducing N and a run started
    # without it is a new dungeon every time.
    #
    # This method reads the size before it enters the alternate screen. The
    # message then stays where the person can read it. Handing the screen back
    # would wipe it.
    #
    # `SizeDetector` is termbuf's internal tier. The stable API cannot answer
    # how big a terminal is without opening it. The other way to find out is
    # to enter the alternate screen and leave it again.
    def self.open(seed : UInt64?, flicker : Bool = true,
                  generate : Bool = true, console : Bool = false,
                  store : Save::Store? = nil, character : String? = nil) : Session?
      size = TermBuf::SizeDetector.detect

      unless Ui::Screen.fits? size.columns, size.rows
        STDERR.puts Ui::Screen.too_small(size.columns, size.rows)
        return
      end

      ran = nil.as Session?
      previous = nil.as String?

      TermBuf::Terminal.open do |terminal|
        loop do
          played = new terminal, Rng.for(seed), flicker, generate, console,
            store, character, previous
          ran = played
          played.run

          # The name was asked for once. A second run starts from the title
          # screen again, so it asks again. What it asks offers the name the
          # run that just ended was under, because that is what somebody who
          # answered "play again" usually wants.
          character = nil
          previous = played.play.game.player.name.presence

          break unless played.again?
        end
      end

      ran
    end

    # The device. This class touches no other.
    getter terminal : TermBuf::Terminal

    # The run's randomness.
    getter rng : Rng

    # Everything that is shown. Everything the keys do.
    getter play : Ui::Play

    # The widget tree, its focus and its router.
    getter app : Ui::Widgets::App

    # The terminal's own cursor.
    getter cursor : TermBuf::Cursor

    # The list of keys that work here. `F1` and `?` show it.
    getter help : Ui::Widgets::HelpOverlay

    # Whether the terminal is reporting the mouse.
    #
    # This starts on. Pointing at a square is the quickest way to read a map.
    # `M` turns it off. A terminal reporting the mouse no longer lets the
    # person select text with it.
    getter? mousing : Bool = false

    def initialize(@terminal : TermBuf::Terminal, @rng : Rng,
                   flicker : Bool = true, generate : Bool = true,
                   console : Bool = false, store : Save::Store? = nil,
                   character : String? = nil, previous : String? = nil)
      size = @terminal.size
      bounds = TermBuf::Rect.full size.columns, size.rows

      @play = Ui::Play.new(generate ? Game.dug(@rng) : Game.start(@rng), console)
      @play.store = store
      @play.previous_name = previous
      @play.fit size.columns, size.rows

      @app = Ui::Widgets::App.new @terminal, @play.root, bounds,
        @terminal.events, @terminal.policy
      @cursor = @terminal.cursor bounds
      @play.app = @app

      @app.after = ->(span : Time::Span) { @terminal.after span }
      @app.cancel = ->(nonce : UInt64) { @terminal.cancel nonce }
      @app.copy = ->(text : String) { @terminal.clipboard.copy text }
      @app.images = @terminal.images
      @app.on_event = ->(event : TermBuf::Event) { unclaimed event }

      @help = Ui::Keys.install(@app) { @play.confirm_quit }
      @app.keymap = @app.keymap
        .merge(@play.bindings)
        .merge(Ui::Keys.mousing { self.mousing = !mousing? })

      self.mousing = true

      # One layout runs before the camera is pointed. An unmeasured window
      # has no middle to put anything in.
      @app.frame { }
      @play.look_at_player

      @play.flicker.burning = flicker
      waver if flicker

      # `--character` says who is playing, so the title screen and the name
      # question are both answered already.
      character ? @play.play_as(character) : @play.show_title
    end

    # Schedules the next tick of the flames, and the one after it.
    #
    # This is the one thing in the game driven by a clock rather than a turn.
    # The timer arrives on the same channel as the keystrokes, in order with
    # them, so a tick cannot land in the middle of a turn.
    #
    # It moves nothing the game decides. `Play#waver` shifts which shade a
    # lit square draws at and no more, so the paint that follows sends the
    # squares whose color moved and nothing else.
    private def waver : Nil
      @app.after(Ui::Flicker::PERIOD) do
        @play.waver
        waver
      end
    end

    # The run.
    def game : Game
      @play.game
    end

    # Whether the person asked for another run when this one ended.
    def again? : Bool
      @play.again?
    end

    # Draws, waits, and repeats until something ends the run.
    #
    # The `ensure` puts the pointer shape back however the run ends.
    # `Terminal#close` restores every mode termbuf set. termbuf never sets
    # `OSC 22`. This class set it. This class restores it.
    def run : Nil
      loop do
        draw

        break if @play.finished?
        break unless @app.wait
      end
    ensure
      tell @play.pointer_away
    end

    # Turns mouse reporting on or off. Writes the new state to the status
    # line.
    #
    # Nothing asks the terminal for the mouse uninvited. `Terminal#close`
    # restores mouse reporting as well as this method. A run that ends any way
    # at all leaves the terminal able to select text again.
    def mousing=(wanted : Bool) : Bool
      return wanted if wanted == @mousing

      @mousing = wanted

      if wanted
        @terminal.enable TermBuf::Tty::MOUSE_SGR_ANY
      else
        @terminal.disable TermBuf::Tty::MOUSE_SGR_ANY
        tell @play.pointer_away
      end

      status
      wanted
    end

    # Tells the status line whether the mouse is reporting. The terminal knows
    # that. The game does not.
    private def status : Nil
      @play.mousing = mousing?
    end

    # Sends *sequence*. Sends nothing when *sequence* is `nil`.
    private def tell(sequence : String?) : Nil
      @terminal.passthrough sequence if sequence
    end

    # An event no widget wanted.
    #
    # Two kinds get this far. A mouse report gets here because the map pane
    # draws squares and holds nothing about what is on them. A resize gets
    # here because the tree has to be laid out again. `Screen#fit` then decides
    # what is still worth showing, before anything draws against the new
    # rectangles.
    private def unclaimed(event : TermBuf::Event) : Nil
      case event
      when TermBuf::Events::Mouse  then tell @play.pointed(event.x, event.y, Session.click?(event))
      when TermBuf::Events::Resize then resized event
      end
    end

    # Whether *event* is a button going down on the map rather than the
    # pointer moving.
    #
    # A wheel notch arrives as a press too. A notch is not a click. It says
    # nothing about where the person wants to look.
    def self.click?(event : TermBuf::Events::Mouse) : Bool
      event.action.press? && !event.button.wheel?
    end

    private def resized(resize : TermBuf::Events::Resize) : Nil
      size = resize.size
      bounds = TermBuf::Rect.full size.columns, size.rows

      @play.fit size.columns, size.rows
      @app.resize bounds
      @cursor.region.bounds = bounds

      # The square the pointer was over has moved.
      tell @play.pointer_away
    end

    # One frame. Lay out, draw, place the terminal's own cursor, and send the
    # difference.
    private def draw : Nil
      @app.frame do |focused|
        # The pointer wins, then the examine cursor. The person is moving one
        # of those now. The person is not moving whatever has the keyboard.
        spot = @play.cursor || focused

        if spot
          @cursor.move_to spot[0], spot[1]
          @terminal.hardware_cursor = @cursor
        else
          @terminal.hide_cursor
        end
      end

      @terminal.paint
    end
  end
end
