require "compress/gzip"
require "json"
require "../../roguelike"

module Roguelike
  module Events
    # Every event a recorded run emits, one JSON line each, gzipped.
    #
    # The file sits beside the replay log, named from it, and lives as long
    # as the log does. `Replay::Log` opens one, hands it each action, and
    # pauses and closes it with itself.
    #
    # The first line is a header. Every event line is the event's own JSON
    # with `turn` and `floor` in front and the event's `Facts` merged in. A
    # `stats` line follows any event that moved one of the character's
    # numbers. Pause, resume and footer lines mirror the replay log's, so a
    # reader can drop the lines of a branch a save went back past.
    #
    # The lines an action writes wait until the replay log has written the
    # action. A refused action is not in the replay log, and its lines are
    # dropped, so a replay of the log rebuilds this file.
    #
    # Each pause ends one gzip member and flushes it. The next line starts
    # another. A file cut off between pauses loses the lines since the last
    # one, and a resume puts the rest of the file back in order first.
    class Writer
      # The number in the header. It changes when a reader has to.
      FORMAT = 1

      # Event fields written under another name, because the line already
      # has a field of that name. `Event::Climbed#floor` is the floor's id,
      # and the line's `floor` is its depth.
      RENAMED = {"floor" => "floor_id"}

      # What the file name adds to the replay log's stem.
      SUFFIX = ".events.jsonl.gz"

      # Whether a recorded run writes events. `--no-events` clears it.
      class_property? enabled : Bool = true

      # The version the header and resume lines name, which is this build's.
      def self.version : String
        "#{VERSION}+g#{BUILD}"
      end

      # Where the events of the log at *log* go.
      def self.path_for(log : Path) : Path
        Path["#{log.to_s.rchop Replay::Naming::SUFFIX}#{SUFFIX}"]
      end

      # A new file for *game*, beside the log at *log* whose id is *id*.
      # `nil` when events are off or the file will not open.
      #
      # *version* is the build the header names. A backfill passes the one
      # that recorded the log.
      def self.started(game : Game, log : Path, id : String,
                       version : String = Writer.version) : Writer?
        return unless enabled?

        new game, path_for(log), id, nil, version
      rescue error : ::File::Error
        STDERR.puts "events: #{error.message}"
        nil
      end

      # The file beside *log* carried on, from the save at *pause*.
      #
      # A file that is not there, or that will not read at all, starts
      # again with a header.
      #
      # *version* is the build the resume line names. A backfill passes the
      # one that recorded the resume.
      def self.resumed(game : Game, log : Path, id : String, pause : Int32,
                       version : String = Writer.version) : Writer?
        return unless enabled?

        new game, path_for(log), id, pause, version
      rescue error : ::File::Error
        STDERR.puts "events: #{error.message}"
        nil
      end

      # The file being written.
      getter path : Path

      @game : Game
      @file : ::File

      # The member being written, or `nil` between pauses.
      @member : Compress::Gzip::Writer? = nil

      # The lines of the action being taken.
      @pending = [] of String

      # The last numbers written, and the last noted for the pending lines.
      @stats : Event::Stats? = nil
      @noted : Event::Stats? = nil

      # The kind of the last event in the pending lines.
      @cause : String? = nil

      private def initialize(@game : Game, @path : Path, id : String,
                             pause : Int32?, version : String)
        if pause && Writer.repaired(@path)
          @file = ::File.new @path, "a"
          line({type: "resume", pause: pause, turn: @game.turn,
                game_version: version})
        else
          @file = ::File.new @path, "w"
          line({type: "header", format: FORMAT, game_version: version,
                log: id})
          line({type: "resume", pause: pause, turn: @game.turn}) if pause
        end

        opening = Event::Stats.of @game.player
        opening.cause = pause ? "resume" : "start"
        member << line_for(opening) << '\n'
        @stats = @noted = opening
        flush
      end

      # Whether the file at *path* is there and reads to the end.
      #
      # A file whose last member was cut off is written again from the lines
      # that read whole. One that does not read at all answers false.
      protected def self.repaired(path : Path) : Bool
        return false unless ::File.exists? path

        kept = [] of String
        whole = true
        begin
          ::File.open path do |file|
            Compress::Gzip::Reader.open(file) do |gzip|
              gzip.each_line(chomp: false) do |found|
                unless found.ends_with? '\n'
                  whole = false
                  break
                end

                kept << found
              end
            end
          end
        rescue Compress::Gzip::Error | Compress::Deflate::Error | IO::Error
          whole = false
        end
        return true if whole
        return false if kept.empty?

        ::File.open path, "w" do |file|
          Compress::Gzip::Writer.open(file) { |gzip| kept.each { |found| gzip << found } }
        end
        true
      end

      # Notes *event*, which the game has just emitted.
      #
      # A floor arrival, a level up and the end of the run always write the
      # numbers after them.
      def note(event : Event) : Nil
        @pending << line_for(event)
        @cause = event.kind

        forced = event.is_a?(Event::Climbed) || event.is_a?(Event::LevelUp) ||
                 event.is_a?(Event::Over)
        numbers event.kind, forced
      end

      # Drops the lines of an action that was not taken.
      def drop : Nil
        @pending.clear
        @noted = @stats
        @cause = nil
      end

      # Writes the lines of *action*, which the replay log has just written.
      def commit(action : Action) : Nil
        numbers(@cause || action_name(action), false)

        out = member
        @pending.each { |found| out << found << '\n' }
        @pending.clear
        @stats = @noted
        @cause = nil
      end

      # Writes a pause line, as the replay log writes pause *number*, and
      # ends the member so the file reads whole.
      def pause(number : Int32) : Nil
        line({type: "pause", pause: number, turn: @game.turn})
        flush
      end

      # Writes a footer line when *footer* says the log has one, and closes
      # the file.
      def close(footer : Bool) : Nil
        line({type: "footer", turn: @game.turn,
              outcome: @game.outcome.to_s.downcase}) if footer
        flush
        @file.close
      end

      # Notes a stats line when the numbers differ from the last ones, or
      # when *forced*. *cause* names what moved them.
      private def numbers(cause : String, forced : Bool) : Nil
        now = Event::Stats.of @game.player
        last = @noted
        return if !forced && last && last.same?(now)

        now.cause = cause
        @pending << line_for(now)
        @noted = now
      end

      # What *action* is called in its own JSON.
      private def action_name(action : Action) : String
        JSON.parse(action.to_json)["t"]?.try(&.as_s?) || "action"
      end

      # The line for *event*, at the turn and on the floor the run is at.
      private def line_for(event : Event) : String
        fields = JSON.parse(event.to_json).as_h
        event.facts.try do |facts|
          JSON.parse(facts.to_json).as_h.each { |key, value| fields[key] ||= value }
        end

        JSON.build do |json|
          json.object do
            json.field "turn", @game.turn
            json.field "floor", @game.depth
            json.field "kind", fields["kind"]
            fields.each do |key, value|
              next if key == "kind" || key == "text"

              json.field RENAMED.fetch(key, key), value
            end
            fields["text"]?.try { |text| json.field "text", text }
          end
        end
      end

      # Writes *fields* as one line now, outside any action.
      private def line(fields) : Nil
        member << fields.to_json << '\n'
      end

      # The member being written, started when there is none.
      private def member : Compress::Gzip::Writer
        @member ||= Compress::Gzip::Writer.new(@file)
      end

      # Ends the member being written and flushes the file.
      private def flush : Nil
        @member.try &.close
        @member = nil
        @file.flush
      end
    end
  end
end
