require "digest/sha256"
require "../roguelike"
require "./submit/endpoint"
require "./submit/meta"
require "./submit/parcel"
require "./submit/outbox"
require "./submit/client"
require "./submit/consent"

module Roguelike
  # Sending replay logs to the developer.
  #
  # A run that is recorded can be sent, with the save it was written with,
  # so that a bug found in play can be reproduced. Each send is a `Parcel`
  # in the `Outbox` directory. `Save::Store#write` and `Replay::Log#finish`
  # put parcels there while a run is played. `.flush` sends them when the
  # process has given the terminal back, so a send never holds up a turn.
  #
  # Nothing is sent without the person's agreement. `Consent` asks once and
  # keeps the answer. `--autosubmit` turns the feature on and
  # `--no-autosubmit` turns it off. A test build has it on by default, and
  # every other build has it off. That default is the only way the two
  # builds differ here.
  module Submit
    # The token a request carries. It tells the server a game sent the
    # request. It is public, and it is not a credential.
    TOKEN = "crystal-roguelike-test"

    # The largest file the server takes, in bytes.
    LIMIT = 32 * 1024 * 1024

    # What this binary was built for, as the server names platforms.
    PLATFORM = {{ (flag?(:darwin) ? "macos" : flag?(:linux) ? "linux" : flag?(:win32) ? "windows" : "other") +
                  "-" + (flag?(:aarch64) ? "aarch64" : flag?(:x86_64) ? "x86_64" : "other") }}

    # Where parcels wait to be sent, or `nil` when nothing is sent.
    class_property outbox : Outbox? = nil

    # What the outbox directory is called under the game's own.
    OUTBOX = "outbox"

    # The game's own state directory. See `Save::Store.default`.
    def self.root : Path
      Path[Save.state_home] / "roguelike"
    end

    # Decides whether this process sends, and asks the person if it has to.
    #
    # *wanted* is what the command line said, or the build's default.
    # *explicit* is whether `--autosubmit` was typed, which asks again after
    # an earlier no. Nobody is asked unless *input* is a terminal.
    #
    # Sending needs a log. When this process would otherwise record nothing,
    # agreeing turns recording on in the test logs directory.
    def self.arrange(wanted : Bool, explicit : Bool, root : Path = Submit.root,
                     input : IO = STDIN, output : IO = STDOUT) : Bool
      return false unless wanted

      consent = Consent.new root
      agreed = consent.answer
      agreed = nil if explicit && agreed == false

      if agreed.nil?
        tty = input.as?(IO::FileDescriptor).try(&.tty?) || false
        return false unless tty

        agreed = consent.ask input, output
      end

      return false unless agreed

      @@outbox = Outbox.new root / OUTBOX
      Replay::Log.always ||= Replay::Log.test_logs
      true
    end

    # Puts a save and the log it paused in the outbox.
    #
    # *mark* is what the save names: the log file and its pause number,
    # which is the parcel's sequence number. A save of a run nothing records
    # has none, and nothing is sent for it.
    def self.saved(game : Game, mark : Replay::Mark?, save : Path) : Nil
      outbox = @@outbox
      return unless outbox && mark

      log = Path[mark.log]
      meta = Meta.of game, Submit.log_id(log)
      outbox.pack meta, mark.pause, log, save
    rescue error : File::Error | IO::Error | JSON::Error | Replay::Error
      STDERR.puts "replay upload: #{error.message}"
    end

    # Puts a log that has just been closed in the outbox.
    #
    # The sequence number is one past the last pause, so the parcel for the
    # end of a run sorts after every save in it.
    def self.closed(game : Game, log : Path, pauses : Int32) : Nil
      outbox = @@outbox
      return unless outbox

      meta = Meta.of game, Submit.log_id(log)
      outbox.pack meta, pauses + 1, log, nil
    rescue error : File::Error | IO::Error | JSON::Error | Replay::Error
      STDERR.puts "replay upload: #{error.message}"
    end

    # Sends every parcel in the outbox to *url*, and says how it went on
    # *output*, one line per parcel.
    #
    # An empty *url* means this binary has nowhere to send to. The parcels
    # stay where they are and nothing is said.
    def self.flush(url : String = ENDPOINT, output : IO = STDOUT) : Nil
      outbox = @@outbox
      return unless outbox
      return if url.empty?

      outbox.flush Client.new(url), output
    end

    # The identity of the log at *path* for the server.
    #
    # It is 32 hex digits taken from the header, so a run carried on from a
    # save in another process keeps the identity of the file it goes on in.
    def self.log_id(path : Path) : String
      File.each_line path do |line|
        next unless line.includes? %("type":"header")

        return log_id Replay::Header.from_json(line)
      end

      raise Replay::Error.new "#{path} has no header"
    end

    # :ditto:
    def self.log_id(header : Replay::Header) : String
      Digest::SHA256.hexdigest("#{header.started_at.to_utc.to_rfc3339}|#{header.seed}|#{header.player}")[0, 32]
    end
  end
end
