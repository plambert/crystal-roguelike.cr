require "json"
require "../roguelike"

module Roguelike
  # What has just happened, oldest first.
  #
  # The log holds English text. The model composes it. `Terrain#label` and
  # `Terrain#description` are English too, so this is the choice already made
  # for the rest of the model. Translating a run would mean changing all three
  # together.
  #
  # A save file holds the log. A person who comes back to a run reads the last
  # thing that happened to them.
  class MessageLog
    include JSON::Serializable

    # How many messages are kept. Older ones are dropped.
    LIMIT = 200

    # The messages, oldest first.
    getter lines : Array(String)

    # How many messages have ever been added.
    #
    # `#size` stops growing once the log is full, because a line added then
    # drops the oldest one. This one goes on counting. A caller that wants to
    # know how many lines a turn wrote subtracts two of these.
    #
    # It is not written out. A save holds the messages rather than the tally,
    # and a run read back counts from zero.
    @[JSON::Field(ignore: true)]
    getter written : Int32 = 0

    # The round each message was written in, oldest first.
    #
    # A round is one action of the character's and what the world did in
    # answer. A message written between actions belongs to the round the next
    # action will close. A save written before rounds were kept has none, and
    # those lines read as older than every round.
    getter rounds : Array(Int32) = [] of Int32

    # The round now being written.
    getter round : Int32 = 0

    def initialize(@lines : Array(String) = [] of String)
    end

    # Closes the round being written. `Game` calls this when the character
    # can act again.
    def next_round : Nil
      @round += 1
    end

    # Whether the message at *index* is recent.
    #
    # That is the last round closed, which holds the character's latest
    # action and its consequences, and the round after it, which holds
    # anything said since.
    def current?(index : Int32) : Bool
      found = round_of index
      !found.nil? && found >= 0 && found >= @round - 1
    end

    # How many of the newest messages are recent.
    def current : Int32
      count = 0
      @lines.size.times do |back|
        break unless current?(@lines.size - 1 - back)

        count += 1
      end
      count
    end

    # The round of the message at *index*. `nil` when it has none recorded.
    def round_of(index : Int32) : Int32?
      slot = index - (@lines.size - @rounds.size)
      slot >= 0 ? @rounds[slot]? : nil
    end

    # Replaces every message with *lines*, all in the round being written.
    def replace(lines : Array(String)) : Nil
      @lines.clear
      @rounds.clear

      lines.each do |line|
        @lines << line
        @rounds << @round
      end
    end

    # Adds *line*. Drops the oldest message when the log is full.
    #
    # A message identical to the last one is not added twice. A wall bumped
    # ten times reads better as one line than as ten. The line already there
    # moves into the round being written, because it has just happened again.
    def add(line : String) : Nil
      return if line.empty?

      # Lines set straight onto `#lines`, or loaded from a save with no
      # rounds, leave the two arrays unequal. The older ones are padded out.
      missing = @lines.size - @rounds.size
      if missing > 0
        @rounds = Array.new(missing, -1) + @rounds
      elsif missing < 0
        @rounds = @rounds.last @lines.size
      end

      if @lines.last? == line
        @rounds[-1] = @round
        return
      end

      @lines << line
      @rounds << @round
      @written += 1
      if @lines.size > LIMIT
        @lines.shift
        @rounds.shift
      end
    end

    # How many messages there are.
    def size : Int32
      @lines.size
    end

    # Whether nothing has happened yet.
    def empty? : Bool
      @lines.empty?
    end

    # The most recent message. `nil` when nothing has happened yet.
    def last? : String?
      @lines.last?
    end

    # Takes every message out.
    def clear : Nil
      @lines.clear
      @rounds.clear
    end
  end
end
