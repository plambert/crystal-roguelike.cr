require "json"

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

    def initialize(@lines : Array(String) = [] of String)
    end

    # Adds *line*. Drops the oldest message when the log is full.
    #
    # A message identical to the last one is not added twice. A wall bumped
    # ten times reads better as one line than as ten.
    def add(line : String) : Nil
      return if line.empty?
      return if @lines.last? == line

      @lines << line
      @written += 1
      @lines.shift if @lines.size > LIMIT
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
    end
  end
end
