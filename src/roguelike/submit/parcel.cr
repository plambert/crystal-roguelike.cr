require "compress/gzip"
require "../../roguelike"

module Roguelike
  module Submit
    # One send, waiting in the outbox as a directory.
    #
    # The directory is named `<log>-<seq>`. It holds `meta.json`, a gzipped
    # copy of the log as `replay.jsonl.gz`, a gzipped copy of the save as
    # `save.json.gz` when the parcel was packed with one, and a copy of the
    # events file as `events.jsonl.gz` when the run writes one. The copies are
    # taken when the parcel is packed, so what is sent is what the run
    # looked like at that moment, whatever the live file does afterwards.
    class Parcel
      # What the server calls each file.
      META   = "meta"
      REPLAY = "replay"
      SAVE   = "save"
      EVENTS = "events"

      # The logical names used for paths in uploaded copies.
      UPLOAD_REPLAY = "replay.jsonl"
      UPLOAD_SAVE   = "save.json"

      # What each kind is called on disk here.
      NAMES = {
        META   => "meta.json",
        REPLAY => "replay.jsonl.gz",
        SAVE   => "save.json.gz",
        EVENTS => "events.jsonl.gz",
      }

      # One file in the parcel.
      record Piece, kind : String, path : Path, size : Int64

      # The directory.
      getter directory : Path

      # What the parcel says about its run.
      getter meta : Meta

      # The parcel's sequence number. See `Submit.saved` and `Submit.closed`.
      getter seq : Int32

      def initialize(@directory : Path, @meta : Meta, @seq : Int32)
      end

      # Packs *log*, *save* and *events* for *meta* into *directory*, as
      # sequence number *seq*. The events file is gzipped already, and goes
      # in as it is.
      def self.pack(directory : Path, meta : Meta, seq : Int32, log : Path,
                    save : Path?, events : Path? = nil) : Parcel
        Dir.mkdir_p directory

        File.write directory / NAMES[META], meta.to_json
        Parcel.compress_replay log, directory / NAMES[REPLAY]
        Parcel.compress_save save, directory / NAMES[SAVE] if save
        File.copy events, directory / NAMES[EVENTS] if events

        new directory, meta, seq
      end

      # The parcel in *directory*, read back from its files, or `nil` for a
      # directory that is not one.
      def self.open(directory : Path) : Parcel?
        name = directory.basename
        dash = name.rindex '-'
        return unless dash

        seq = name[(dash + 1)..].to_i?
        return unless seq

        meta = Meta.from_json File.read(directory / NAMES[META])
        new directory, meta, seq
      rescue File::Error | JSON::Error
        nil
      end

      # What the directory for *meta* at *seq* is called.
      def self.name(meta : Meta, seq : Int32) : String
        "#{meta.log}-#{seq.to_s.rjust 3, '0'}"
      end

      # The files to send. The log, the save and the events go in that
      # order and the meta goes last, so a listing that has the meta has the
      # rest.
      def pieces : Array(Piece)
        [REPLAY, SAVE, EVENTS, META].compact_map do |kind|
          path = @directory / NAMES[kind]
          next unless File.exists? path

          Piece.new kind, path, File.size(path)
        end
      end

      # Takes the parcel out of the outbox.
      def remove : Nil
        pieces.each { |piece| File.delete piece.path }
        Dir.delete @directory
      end

      # Writes the replay to *target* with path-bearing continuation metadata
      # replaced by logical names.
      protected def self.compress_replay(source : Path, target : Path) : Nil
        File.open source do |input|
          File.open target, "w" do |output|
            Compress::Gzip::Writer.open(output) do |packed|
              input.each_line(chomp: false) { |line| packed << replay_line(line) }
            end
          end
        end
      end

      # Writes the save to *target* with path-bearing replay metadata replaced
      # by logical names.
      protected def self.compress_save(source : Path, target : Path) : Nil
        held = Save::Held.from_json File.read(source)
        replay = held.replay.try do |mark|
          Replay::Mark.new UPLOAD_REPLAY, mark.pause
        end
        saved = Save::Held.new held.name, held.version, held.saved, held.turn,
          held.level, held.outcome, held.game, replay

        File.open target, "w" do |output|
          Compress::Gzip::Writer.open(output) { |packed| packed << saved.to_pretty_json }
        end
      end

      # One replay line, with its continuation metadata sanitized when it is
      # a header.
      private def self.replay_line(line : String) : String
        kind = begin
          Replay::Reading::Kind.from_json(line).type
        rescue JSON::ParseException
          return line
        end
        return line unless kind == "header"

        carried = ReplayPaths.from_json(line).continued
        return line unless carried

        header = Replay::Header.from_json line
        continued = Replay::Carried.new UPLOAD_SAVE, carried.saved_at, carried.turn,
          carried.log ? UPLOAD_REPLAY : nil, carried.pause

        sanitized = header.with_continued continued

        ending = line.ends_with?('\n') ? "\n" : ""
        sanitized.to_json + ending
      end

      # The path-bearing part of a replay header.
      private struct ReplayPaths
        include JSON::Serializable

        getter continued : Replay::Carried?
      end
    end
  end
end
