require "compress/gzip"
require "../../roguelike"

module Roguelike
  module Submit
    # One send, waiting in the outbox as a directory.
    #
    # The directory is named `<log>-<seq>`. It holds `meta.json`, a gzipped
    # copy of the log as `replay.jsonl.gz`, and a gzipped copy of the save
    # as `save.json.gz` when the parcel was packed with one. The copies are
    # taken when the parcel is packed, so what is sent is what the run
    # looked like at that moment, whatever the live file does afterwards.
    class Parcel
      # What the server calls each file.
      META   = "meta"
      REPLAY = "replay"
      SAVE   = "save"

      # What each kind is called on disk here.
      NAMES = {
        META   => "meta.json",
        REPLAY => "replay.jsonl.gz",
        SAVE   => "save.json.gz",
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

      # Packs *log* and *save* for *meta* into *directory*, as sequence
      # number *seq*.
      def self.pack(directory : Path, meta : Meta, seq : Int32, log : Path,
                    save : Path?) : Parcel
        Dir.mkdir_p directory

        File.write directory / NAMES[META], meta.to_json
        Parcel.compress log, directory / NAMES[REPLAY]
        Parcel.compress save, directory / NAMES[SAVE] if save

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

      # The files to send, the log before the save and the meta last, so a
      # listing that has the meta has the rest.
      def pieces : Array(Piece)
        [REPLAY, SAVE, META].compact_map do |kind|
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

      # Writes *source* gzipped to *target*.
      protected def self.compress(source : Path, target : Path) : Nil
        File.open source do |input|
          File.open target, "w" do |output|
            Compress::Gzip::Writer.open(output) { |packed| IO.copy input, packed }
          end
        end
      end
    end
  end
end
