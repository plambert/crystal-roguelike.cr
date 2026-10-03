require "../../roguelike"

module Roguelike
  module Submit
    # The directory parcels wait in until they are sent.
    #
    # A parcel that will not send stays, and the next process that flushes
    # tries it again. A parcel that sends is removed. Nothing is retried
    # within one flush.
    class Outbox
      # Where the parcels are.
      getter directory : Path

      def initialize(@directory : Path)
      end

      # Something that takes a parcel. `Client` is the one that talks to the
      # server. A spec gives an outbox one that does not.
      module Carrier
        # Sends every piece of *parcel*. Raises `Error` when one will not go.
        abstract def send(parcel : Parcel) : Nil
      end

      # Packs a parcel for *meta* and puts it here.
      def pack(meta : Meta, seq : Int32, log : Path, save : Path?) : Parcel
        Parcel.pack @directory / Parcel.name(meta, seq), meta, seq, log, save
      end

      # The parcels here, oldest first.
      def parcels : Array(Parcel)
        return [] of Parcel unless Dir.exists? @directory

        Dir.children(@directory).sort.compact_map do |name|
          path = @directory / name
          next unless Dir.exists? path

          Parcel.open path
        end.sort_by! { |parcel| File.info(parcel.directory).modification_time }
      end

      # Sends every parcel with *carrier*, saying on *output* how each went.
      def flush(carrier : Carrier, output : IO) : Nil
        parcels.each do |parcel|
          size = parcel.pieces.sum &.size
          carrier.send parcel
          parcel.remove
          output.puts "Sent replay #{parcel.meta.log[0, 8]}… (#{Outbox.sized size})"
        rescue error : Error | IO::Error | File::Error
          output.puts "Could not send replay #{parcel.meta.log[0, 8]}…: #{error.message}. It will be tried again next time."
        end
      end

      # *bytes* as a person reads it.
      def self.sized(bytes : Int) : String
        return "#{bytes} B" if bytes < 1024
        return "#{(bytes / 1024.0).round 1} KB" if bytes < 1024 * 1024

        "#{(bytes / (1024.0 * 1024)).round 1} MB"
      end
    end

    # Something that stopped a send.
    class Error < Exception
    end
  end
end
