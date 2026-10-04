require "json"
require "termbuf"

# Extraction candidate: `TermBuf::TerminalInfo`, for termbuf.cr.
#
# What the terminal is and what termbuf made of it, as one line of JSON. It
# is for a bug report from a machine nobody else can sit at. The report
# carries the environment variables detection reads, the capabilities the
# environment alone suggests, the capabilities the probe settled on, what the
# terminal called itself, and the chain of processes above this one, which
# is where the terminal's own name usually turns up when nothing else gives
# it.
#
# The probe runs the way `Terminal.open` runs it: raw mode first, on the
# alternate screen when the environment says there is one, and the terminal
# is handed back before anything is printed.
#
# This module is written in `TermBuf` rather than in `Roguelike`. Extracting
# it is then a file move with no edits.
module TermBuf
  module TerminalInfo
    extend self

    # The variables detection reads, and a few that name a terminal or say
    # what sits between it and this process. Only the ones set are reported.
    VARIABLES = %w[
      TERM COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION VTE_VERSION NO_COLOR
      TMUX STY SSH_TTY SSH_CONNECTION KITTY_WINDOW_ID GHOSTTY_RESOURCES_DIR
      WEZTERM_EXECUTABLE ALACRITTY_WINDOW_ID WT_SESSION TERMBUF_CAPS
      TERMBUF_QUIRKS LANG LC_ALL LC_CTYPE COLUMNS LINES
    ]

    # How many processes up the chain to name.
    ANCESTORS = 6

    # The report.
    class Report
      include JSON::Serializable

      # Which of the three standard streams is a terminal.
      getter tty : Hash(String, Bool)

      # The screen size, as `SizeDetector` finds it.
      getter size : Hash(String, Int32)

      # The variables in `VARIABLES` that are set, with their values.
      getter env : Hash(String, String)

      # What the environment alone suggests the terminal can do.
      getter guessed : Array(String)

      # Whether the terminal answered the probe at all.
      getter? probed : Bool

      # What the terminal called itself, when it was asked and answered.
      @[JSON::Field(emit_null: true)]
      getter name : String?

      # What the probe and the overrides settled on. This is what a program
      # opening the terminal gets.
      getter capabilities : Array(String)

      # Problems the resolver would have told an application about.
      getter warnings : Array(String)

      # What the terminal is known to get wrong.
      getter quirks : String

      # The names of the processes above this one, nearest first.
      getter ancestors : Array(String)

      def initialize(@tty, @size, @env, @guessed, @probed, @name,
                     @capabilities, @warnings, @quirks, @ancestors)
      end
    end

    # The report for the terminal on *input* and *output*.
    #
    # The probe runs only when both are the terminal. Otherwise the report
    # says what the environment alone suggests, with `probed` false.
    def gather(input : IO = STDIN, output : IO = STDOUT,
               env : Hash(String, String) = ENV.to_h) : Report
      guessed = EnvironmentDetector.detect env
      resolved = resolve guessed, input, output, env

      Report.new(
        {"stdin" => terminal?(STDIN), "stdout" => terminal?(STDOUT), "stderr" => terminal?(STDERR)},
        size(env),
        VARIABLES.each_with_object({} of String => String) { |name, found| env[name]?.try { |value| found[name] = value } },
        names(guessed),
        resolved.probed,
        resolved.name,
        names(resolved.capabilities),
        resolved.warnings,
        resolved.quirks.to_s,
        ancestors
      )
    end

    # Asks the terminal, the way `Terminal.open` asks it, and hands it back.
    private def resolve(guessed : Capabilities, input : IO, output : IO,
                        env : Hash(String, String)) : CapabilityResolver::Result
      tty = Tty.new input, output
      return CapabilityResolver.resolve env unless tty.managed?

      begin
        tty.raw!
        hidden = tty.enter_alternate CapabilityOverrides.apply(guessed, env).capabilities
        found = CapabilityResolver.resolve env, input, output
        tty.scrub_line unless hidden
        found
      ensure
        tty.leave
      end
    end

    # The names of the capabilities in *capabilities*, in enum order.
    def names(capabilities : Capabilities) : Array(String)
      found = [] of String
      capabilities.flags.each { |flag| found << flag.to_s }
      found
    end

    private def terminal?(io : IO) : Bool
      io.as?(IO::FileDescriptor).try(&.tty?) || false
    end

    private def size(env : Hash(String, String)) : Hash(String, Int32)
      found = SizeDetector.detect env: env
      {"columns" => found.columns, "rows" => found.rows}
    end

    # The names of the processes above this one, nearest first, up to
    # `ANCESTORS` of them or the first process, whichever comes first.
    #
    # `ps` answers it on every system that has `ps`. On Windows there is no
    # `ps`, and the chain is left empty until something else answers it.
    def ancestors : Array(String)
      found = [] of String
      {% unless flag?(:win32) %}
        begin
          pid = Process.ppid
          ANCESTORS.times do
            break if pid <= 1

            output = IO::Memory.new
            status = Process.run "ps", ["-o", "ppid=,comm=", "-p", pid.to_s],
              output: output, error: Process::Redirect::Close
            break unless status.success?

            parent, _, name = output.to_s.strip.partition ' '
            break if name.empty?

            found << File.basename(name.strip)
            pid = parent.to_i? || 0
          end
        rescue IO::Error
          # The chain ends where ps stopped answering.
        end
      {% end %}
      found
    end
  end
end
