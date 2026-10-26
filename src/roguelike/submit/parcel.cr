require "compress/gzip"
require "random/secure"
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

      alias GzipError = Compress::Gzip::Error | Compress::Deflate::Error
      LOCK  = ".parcel-transaction.lock"
      STATE = ".parcel-state.json"
      OWNER = ".parcel-owner"

      record State, version : Int32, save : Bool, token : String do
        include JSON::Serializable
      end

      # One file in the parcel.
      record Piece, kind : String, path : Path, size : Int64

      # The directory.
      getter directory : Path

      # What the parcel says about its run.
      getter meta : Meta

      # The parcel's sequence number. See `Submit.saved` and `Submit.closed`.
      getter seq : Int32

      # Whether a save was part of the packaged contents.
      getter? has_save : Bool

      getter state_token : String?

      def initialize(@directory : Path, @meta : Meta, @seq : Int32,
                     @has_save : Bool, @state_token : String?)
      end

      # File renames are isolated so publication failures can be exercised
      # without relying on platform permissions or timing.
      class Filesystem
        def rename(source : Path, target : Path) : Nil
          File.rename source, target
        end
      end

      # Packs *log*, *save* and *events* for *meta* into *directory*, as
      # sequence number *seq*. The events file is gzipped already, and goes
      # in as it is.
      def self.pack(directory : Path, meta : Meta, seq : Int32, log : Path,
                    save : Path?, events : Path? = nil,
                    filesystem : Filesystem = Filesystem.new) : Parcel
        locked directory do
          pack_locked directory, meta, seq, log, save, events, filesystem
        end
      end

      private def self.pack_locked(directory : Path, meta : Meta, seq : Int32,
                                   log : Path, save : Path?, events : Path?,
                                   filesystem : Filesystem) : Parcel
        Dir.mkdir_p directory.parent

        existing = if File.exists? directory
                     open_locked(directory) || raise IO::Error.new("#{directory} is not a complete parcel")
                   end

        staging = temporary_directory directory.parent, directory.basename, "stage"
        begin
          actual_meta, save_source, events_source = sources meta, save, events, existing
          Parcel.compress_replay log, staging / NAMES[REPLAY]
          if save_source
            if save
              Parcel.compress_save save_source, staging / NAMES[SAVE]
            else
              File.copy save_source, staging / NAMES[SAVE]
            end
          end
          File.copy events_source, staging / NAMES[EVENTS] if events_source
          File.write staging / NAMES[META], actual_meta.to_json
          state = State.new 1, !save_source.nil?, Random::Secure.hex(12)
          File.write staging / STATE, state.to_json
          validate_contents! staging, actual_meta, state

          if existing
            repack directory, staging, filesystem
          else
            filesystem.rename staging, directory
          end

          new directory, actual_meta, seq, state.save, state.token
        ensure
          cleanup_staging staging
        end
      end

      # The parcel in *directory*, read back from its files, or `nil` for a
      # directory that is not one.
      def self.open(directory : Path) : Parcel?
        name = directory.basename
        dash = name.rindex '-'
        return unless dash

        seq = name[(dash + 1)..].to_i?
        return unless seq

        locked(directory, false) { open_locked directory, seq }
      rescue File::Error | IO::Error | JSON::Error
        nil
      end

      private def self.open_locked(directory : Path, seq : Int32? = nil) : Parcel?
        actual_seq = seq || begin
          name = directory.basename
          dash = name.rindex '-'
          return unless dash

          name[(dash + 1)..].to_i?
        end
        return unless actual_seq

        recover directory
        meta = Meta.from_json File.read(directory / NAMES[META])
        state = self.state directory
        has_save = state ? state.save : File.file?(directory / NAMES[SAVE])
        validate_contents! directory, meta, state
        new directory, meta, actual_seq, has_save, state.try(&.token)
      end

      # What the directory for *meta* at *seq* is called.
      def self.name(meta : Meta, seq : Int32) : String
        "#{meta.log}-#{seq.to_s.rjust 3, '0'}"
      end

      # The files to send. The log, the save and the events go in that
      # order and the meta goes last, so a listing that has the meta has the
      # rest.
      def pieces : Array(Piece)
        Parcel.locked(@directory, false) { pieces_locked }
      end

      private def pieces_locked : Array(Piece)
        validate_open_state!
        present = present_kinds
        validate_piece_set! present

        [REPLAY, SAVE, EVENTS, META].compact_map do |kind|
          path = @directory / NAMES[kind]
          next unless present.includes? kind

          Piece.new kind, path, File.size(path)
        end
      end

      private def validate_open_state! : Nil
        state = Parcel.state @directory
        return if !state_token && !state
        return if state.try(&.token) == state_token && state.try(&.save) == has_save?

        raise IO::Error.new("#{@directory} changed after it was opened")
      end

      private def present_kinds : Array(String)
        NAMES.compact_map do |kind, name|
          path = @directory / name
          next unless File.exists? path
          raise IO::Error.new("#{path} is not a file") unless File.file? path

          kind
        end
      end

      private def validate_piece_set!(present : Array(String)) : Nil
        unless present.includes?(REPLAY) && present.includes?(META) &&
               present.includes?(EVENTS) == @meta.events? &&
               present.includes?(SAVE) == has_save?
          raise IO::Error.new("#{@directory} is not a complete parcel")
        end
        return if File.size(@directory / NAMES[REPLAY]) > 0 &&
                  File.size(@directory / NAMES[META]) > 0

        raise IO::Error.new("#{@directory} is missing its replay or metadata")
      end

      # Takes the parcel out of the outbox.
      def remove : Nil
        Parcel.locked @directory do
          Parcel.retire_backups @directory
          pieces_locked.each { |piece| File.delete piece.path }
          File.delete @directory / STATE if File.file? @directory / STATE
          Dir.delete @directory if Dir.children(@directory).empty?
        end
      end

      # Retires backups left after a completed repack.
      def self.retire_backups(directory : Path) : Nil
        backups(directory).each { |backup| retire_backup backup, directory }
      end

      # Reads and validates the durable parcel state, or `nil` for legacy
      # parcels that predate it.
      def self.state(directory : Path) : State?
        path = directory / STATE
        return unless File.exists? path
        raise IO::Error.new("#{path} is not a file") unless File.file? path

        value = JSON.parse File.read(path)
        hash = value.as_h?
        version = hash.try(&.[]?("version")).try(&.as_i?)
        save = hash.try(&.[]?("save")).try(&.as_bool?)
        token = hash.try(&.[]?("token")).try(&.as_s?)
        version_value = version || raise IO::Error.new("#{path} is invalid")
        save_value = case save
                     in Bool then save
                     in Nil  then raise IO::Error.new("#{path} is invalid")
                     end
        token_value = token || raise IO::Error.new("#{path} is invalid")
        unless version_value == 1 && token_value.matches?(/\A[0-9a-f]{24}\z/)
          raise IO::Error.new("#{path} is invalid")
        end
        State.new version_value, save_value, token_value
      rescue JSON::Error
        raise IO::Error.new("#{path} is invalid")
      end

      private def self.sources(meta : Meta, save : Path?, events : Path?,
                               existing : Parcel?) : Tuple(Meta, Path?, Path?)
        existing_save = existing.try do |parcel|
          path = parcel.directory / NAMES[SAVE]
          path if File.file? path
        end
        existing_events = existing.try do |parcel|
          path = parcel.directory / NAMES[EVENTS]
          path if File.file? path
        end

        events_source = events || existing_events
        events_included = !events_source.nil?
        if events && !meta.events?
          raise IO::Error.new("events metadata does not match the events file")
        end
        if meta.events? && !events_included
          raise IO::Error.new("events metadata has no events file")
        end

        actual_meta = if meta.events? == events_included
                        meta
                      else
                        Meta.new meta.version, meta.platform, meta.outcome, meta.turn,
                          meta.seed, meta.character, meta.log, events_included, meta.tester
                      end

        {actual_meta, save || existing_save, events_source}
      end

      private def self.repack(directory : Path, staging : Path,
                              filesystem : Filesystem) : Nil
        backup = owned_backup_directory directory.parent, directory.basename
        begin
          transaction_names.each do |name|
            source = directory / name
            filesystem.rename source, backup / name if File.file? source
          end

          old_names = transaction_names.compact_map do |name|
            name if File.file?(backup / name)
          end
          write_manifest backup, old_names, filesystem

          [NAMES[REPLAY], NAMES[SAVE], NAMES[EVENTS], STATE, NAMES[META]].each do |name|
            source = staging / name
            next unless File.file? source

            filesystem.rename source, directory / name
          end
        rescue error : Exception
          begin
            restore_backup directory, backup, filesystem
            cleanup_backup backup
          rescue err : Exception
            raise IO::Error.new(
              "#{error.message}; the previous parcel is recoverable at #{backup}: #{err.message}")
          end
          raise error
        end

        begin
          retire_backup backup, directory
        rescue IO::Error
        end
      end

      private def self.write_manifest(backup : Path, names : Array(String),
                                      filesystem : Filesystem) : Nil
        temporary = backup / ".complete.tmp"
        File.write temporary, names.to_json
        filesystem.rename temporary, backup / ".complete"
      end

      private def self.restore_backup(directory : Path, backup : Path,
                                      filesystem : Filesystem) : Nil
        manifest = backup / ".complete"
        if File.file? manifest
          restore_committed_backup directory, backup, filesystem
        else
          restore_partial_backup directory, backup, filesystem
        end
      end

      private def self.restore_partial_backup(directory : Path, backup : Path,
                                              filesystem : Filesystem) : Nil
        [NAMES[REPLAY], NAMES[SAVE], NAMES[EVENTS], STATE, NAMES[META]].each do |name|
          source = backup / name
          target = directory / name
          next unless File.file? source
          raise IO::Error.new("cannot restore #{target}; it already exists") if File.exists? target

          filesystem.rename source, target
        end
        File.delete(backup / ".complete.tmp") if File.file?(backup / ".complete.tmp")
      end

      private def self.restore_committed_backup(directory : Path, backup : Path,
                                                filesystem : Filesystem) : Nil
        manifest = backup / ".complete"
        names = manifest_names manifest
        [NAMES[REPLAY], NAMES[SAVE], NAMES[EVENTS], STATE].each do |name|
          restore_committed_piece directory, backup, name, names.includes?(name), filesystem
        end

        meta_name = NAMES[META]
        restore_committed_piece directory, backup, meta_name, true, filesystem

        meta = Meta.from_json File.read(directory / meta_name)
        validate_contents! directory, meta, state(directory)
      end

      private def self.manifest_names(manifest : Path) : Array(String)
        value = JSON.parse File.read(manifest)
        elements = value.as_a? || raise IO::Error.new("#{manifest} is invalid")

        names = elements.compact_map(&.as_s?)
        raise IO::Error.new("#{manifest} is invalid") unless names.size == elements.size
        unless names.includes?(NAMES[META]) && names.includes?(NAMES[REPLAY]) &&
               names.uniq == names && names.all? { |name| transaction_names.includes? name }
          raise IO::Error.new("#{manifest} is invalid")
        end
        names
      rescue JSON::Error
        raise IO::Error.new("#{manifest} is invalid")
      end

      private def self.restore_committed_piece(directory : Path, backup : Path,
                                               name : String, required : Bool,
                                               filesystem : Filesystem) : Nil
        target = directory / name
        source = backup / name
        if required
          if File.file? source
            File.delete target if File.exists? target
            filesystem.rename source, target
          elsif !File.file?(target)
            raise IO::Error.new("#{source} and #{target} are both missing")
          end
        elsif File.exists? target
          File.delete target
        end
      end

      private def self.recover(directory : Path,
                               filesystem : Filesystem = Filesystem.new) : Nil
        found = backups directory
        return if found.empty?

        if complete?(directory)
          found.each { |backup| try_retire_backup backup, directory }
          return
        end

        found.each do |backup|
          restore_backup directory, backup, filesystem
          if complete? directory
            retire_backups_safely directory
            return
          end
        end
      end

      private def self.retire_backups_safely(directory : Path) : Nil
        backups(directory).each { |backup| try_retire_backup backup, directory }
      end

      private def self.try_retire_backup(backup : Path, directory : Path) : Nil
        retire_backup backup, directory
      rescue IO::Error
      end

      private def self.complete?(directory : Path) : Bool
        meta = Meta.from_json File.read(directory / NAMES[META])
        validate_contents! directory, meta, state(directory)
        true
      rescue File::Error | IO::Error | JSON::Error
        false
      end

      private def self.validate_contents!(directory : Path, meta : Meta,
                                          state : State?) : Nil
        replay = directory / NAMES[REPLAY]
        metadata = directory / NAMES[META]
        events = directory / NAMES[EVENTS]
        save = directory / NAMES[SAVE]

        validate_required_files! directory, replay, metadata
        validate_events! directory, events, meta.events?
        validate_save_state! directory, save, state

        validate_gzip replay
        validate_gzip events if meta.events?
        validate_save save if File.exists? save
      end

      private def self.validate_required_files!(directory : Path, replay : Path,
                                                metadata : Path) : Nil
        return if File.file?(replay) && File.size(replay) > 0 &&
                  File.file?(metadata) && File.size(metadata) > 0

        raise IO::Error.new("#{directory} is missing its replay or metadata")
      end

      private def self.validate_events!(directory : Path, events : Path,
                                        required : Bool) : Nil
        exists = File.exists? events
        return if exists == required && (!exists || File.file?(events))

        raise IO::Error.new("#{directory} events metadata does not match its files")
      end

      private def self.validate_save_state!(directory : Path, save : Path,
                                            state : State?) : Nil
        return unless state

        exists = File.exists? save
        return if state.save == exists && (!exists || File.file?(save))

        raise IO::Error.new("#{directory} save state does not match its files")
      end

      private def self.validate_gzip(path : Path) : Nil
        File.open(path) do |file|
          Compress::Gzip::Reader.open(file) do |packed|
            buffer = Bytes.new(8192)
            while packed.read(buffer) > 0
            end
          end
        end
      rescue error : File::Error | IO::Error | GzipError
        raise IO::Error.new("#{path} is not a valid gzip file: #{error.message}")
      end

      private def self.validate_save(path : Path) : Nil
        File.open(path) do |file|
          contents = Compress::Gzip::Reader.open(file, &.gets_to_end)
          Save::Held.from_json contents
        end
      rescue error : File::Error | IO::Error | JSON::Error | GzipError
        raise IO::Error.new("#{path} is not a valid save: #{error.message}")
      end

      private def self.backups(directory : Path) : Array(Path)
        return [] of Path unless Dir.exists? directory.parent

        prefix = ".#{directory.basename}.parcel-backup-"
        suffix = "-owned"
        Dir.children(directory.parent).sort.compact_map do |name|
          path = directory.parent / name
          token = if name.starts_with?(prefix) && name.ends_with?(suffix) &&
                     name.size == prefix.size + 24 + suffix.size
                    name[prefix.size, 24]?
                  end
          next unless token.try(&.matches?(/\A[0-9a-f]{24}\z/)) && Dir.exists?(path)
          next unless File.file?(path / OWNER) && File.read(path / OWNER) == token

          path
        end
      end

      private def self.transaction_names : Array(String)
        NAMES.values + [STATE]
      end

      private def self.lock_path(directory : Path) : Path
        directory.parent / ".#{directory.basename}#{LOCK}"
      end

      # Runs *block* while the parcel transaction lock is held.
      def self.locked(directory : Path, blocking : Bool = true, &)
        Dir.mkdir_p directory.parent
        File.open(lock_path(directory), "a+") do |lock|
          lock.flock_exclusive(blocking) { yield }
        end
      end

      private def self.owned_backup_directory(parent : Path, basename : String) : Path
        10.times do
          token = Random::Secure.hex(12)
          path = parent / ".#{basename}.parcel-backup-#{token}-owned"
          begin
            Dir.mkdir path
            begin
              File.write path / OWNER, token
              return path
            rescue error : Exception
              Dir.delete path if Dir.exists?(path)
              raise error
            end
          rescue error : File::Error
            raise error unless File.exists? path
          end
        end
        raise IO::Error.new("could not make a private parcel backup under #{parent}")
      end

      private def self.temporary_directory(parent : Path, basename : String,
                                           role : String) : Path
        10.times do
          path = parent / ".#{basename}.parcel-#{role}-#{Random::Secure.hex(12)}-owned"
          begin
            Dir.mkdir path
            return path
          rescue error : File::Error
            raise error unless File.exists? path
          end
        end
        raise IO::Error.new("could not make a private parcel directory under #{parent}")
      end

      private def self.cleanup_staging(staging : Path) : Nil
        (NAMES.values + [STATE]).each do |name|
          path = staging / name
          File.delete path if File.file? path
        end
        Dir.delete staging if Dir.exists? staging
      rescue File::Error
      end

      private def self.cleanup_backup(backup : Path) : Nil
        (transaction_names + [OWNER, ".complete", ".complete.tmp"]).each do |name|
          path = backup / name
          File.delete path if File.file? path
        end
        Dir.delete backup if Dir.exists? backup
      rescue File::Error
      end

      private def self.retire_backup(backup : Path, directory : Path) : Nil
        internal = transaction_names + [OWNER, ".complete", ".complete.tmp"]
        unknown = Dir.children(backup).reject { |name| internal.includes? name }
        if unknown.empty?
          cleanup_backup backup
          raise IO::Error.new("could not retire parcel backup #{backup}") if Dir.exists? backup
          return
        end

        preserved = directory.parent / ".#{directory.basename}.parcel-preserved-#{Random::Secure.hex(12)}-owned"
        File.rename backup, preserved
      rescue error : File::Error
        raise IO::Error.new("could not preserve parcel backup #{backup}: #{error.message}")
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
