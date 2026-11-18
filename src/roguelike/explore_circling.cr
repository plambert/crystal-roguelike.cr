require "json"
require "../roguelike"

module Roguelike
  module Explore
    # Watches explore for going round the same squares while learning
    # nothing, and turns it away from the goals it was going round between.
    #
    # Explore plans each step afresh from what the character knows. The plan
    # depends on where they stand and what they know, so standing on a square
    # again with the same knowledge plans the same step again, and the steps
    # after it go round the same way. `Game#planned_route` calls `#watch`
    # before it plans a step, and the answer says whether that has happened.
    #
    # Knowledge here is the `Ground` and a *sight* number. The ground is the
    # floor, `Knowledge#revision` and how often the pack changed. Any change
    # to it starts the watch again, because the character learned
    # something. *sight* covers the rest of what a plan reads, such as which
    # items are left to read. A change to it alone does not start the watch
    # again, so a sight that flips back and forth is caught.
    #
    # The first time a square comes round again, every goal explore headed
    # for since the watch started is added to `#avoid`, and explore plans
    # around those. Each later time adds the goals since the time before.
    # After `TRIES` turns away the next one gives up, and explore stops with
    # `Halt::Circling` until the character stands somewhere else or learns
    # something.
    #
    # A step that does not land where it was planned to starts the watch
    # again. `#chose` says where the next step lands. A watch that finds the
    # character anywhere else takes it that something other than explore
    # moved them, or that something stood in the way.
    #
    # A save holds the whole watch, so a run loaded in the middle of a
    # circle goes on as one that never stopped. *sight* is made by `.sight`
    # rather than `Object#hash`, because Crystal seeds its hasher afresh in
    # every process.
    class Circling
      include JSON::Serializable

      # How many times explore is turned away before it gives up.
      TRIES = 3

      # What has to stay the same for a square stood on again to count.
      record Ground, floor : String, revision : Int32, moves : Int32 do
        include JSON::Serializable
      end

      # What `#watch` found.
      enum Watch
        # Nothing has come round. Plan as before.
        Going

        # A square came round, and `#avoid` has grown. Plan again.
        Turned

        # A square came round once too often. Explore stops.
        Stuck
      end

      # The goals explore plans around.
      getter avoid = Set({Int32, Int32}).new

      # How many times explore has been turned away since the watch started.
      getter tries : Int32 = 0

      @ground : Ground? = nil
      @stood = Set({ {Int32, Int32}, Int64 }).new
      @goals = Set({Int32, Int32}).new
      @landing : {Int32, Int32}? = nil
      @watched : { {Int32, Int32}, Int32 }? = nil
      @stuck : {Int32, Int32}? = nil

      def initialize
      end

      # The *sight* number for a plan that reads *unread*, *wells* and
      # whether the character carries a light, *lit*.
      #
      # It is FNV-1a over the numbers in order, the same in every process.
      # Each list is preceded by its length, so two lists cannot run into
      # each other.
      def self.sight(unread : Array({Int32, Int32}), wells : Array({Int32, Int32}),
                     lit : Bool) : Int64
        numbers = [unread.size]
        unread.each { |spot| numbers << spot[0] << spot[1] }
        numbers << wells.size
        wells.each { |spot| numbers << spot[0] << spot[1] }
        numbers << (lit ? 1 : 0)
        fnv(numbers).to_i64!
      end

      # FNV-1a over the four bytes of each of *numbers*, low byte first.
      private def self.fnv(numbers : Array(Int32)) : UInt64
        numbers.reduce(FNV_BASIS) do |found, value|
          4.times.reduce(found) do |inner, shift|
            (inner ^ ((value >> (shift * 8)) & 0xff).to_u64) &* FNV_PRIME
          end
        end
      end

      private FNV_BASIS = 0xcbf29ce484222325_u64
      private FNV_PRIME =      0x100000001b3_u64

      # Records that explore is about to plan a step from *at* on *turn*, and
      # answers whether it has been here before with nothing learned.
      #
      # A second call on the same turn from the same square is the same
      # step, and answers `Going` without counting it again.
      def watch(ground : Ground, at : {Int32, Int32}, sight : Int64,
                turn : Int32) : Watch
        return stuck?(ground, at) ? Watch::Stuck : Watch::Going if @watched == {at, turn}

        @watched = {at, turn}
        restart ground unless ground == @ground && (@landing.nil? || @landing == at)
        @landing = nil
        return Watch::Going if @stood.add?({at, sight})

        @tries += 1
        @avoid.concat @goals
        @goals.clear
        @stood.clear
        @stood << {at, sight}
        return Watch::Turned if @tries <= TRIES

        give_up at
        Watch::Stuck
      end

      # Records that explore headed for *goal* and that its step lands on
      # *landing*.
      def chose(goal : {Int32, Int32}, landing : {Int32, Int32}) : Nil
        @goals << goal
        @landing = landing
      end

      # Gives up where the character stands, as `#watch` does after too
      # many tries. For a plan that finds every goal avoided.
      #
      # The character is expected to stay where they are. Once they stand
      # anywhere else, the watch starts again.
      def give_up(at : {Int32, Int32}) : Nil
        @stuck = at
        @landing = at
      end

      # Whether explore has given up for a character at *at* on *ground*.
      def stuck?(ground : Ground, at : {Int32, Int32}) : Bool
        @stuck == at && @ground == ground
      end

      private def restart(ground : Ground) : Nil
        @ground = ground
        @tries = 0
        @avoid.clear
        @goals.clear
        @stood.clear
        @stuck = nil
      end
    end
  end
end
