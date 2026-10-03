require "../../roguelike"

module Roguelike
  module Submit
    # Whether the person has agreed to sending, kept in a file.
    #
    # The file is `autosubmit` in the game's state directory. It holds `yes`
    # or `no` and when that was said. A missing file means nobody has been
    # asked.
    class Consent
      # What the file is called.
      FILE = "autosubmit"

      # What is said before the question. `%s` is the file the answer goes
      # in.
      TEXT = <<-TEXT
        This build can send the developer a record of each run you play, so that
        a bug found in play can be reproduced.

        What is sent: the seed, every action taken, the messages shown, the
        character's name, the game's version and the platform. Nothing else is
        sent: no paths, host names, user names or anything outside the game.

        A record is sent when the game exits, for each save made and each run
        that ended. --no-autosubmit turns this off for a run. Your answer is
        kept in
          %s
        and asking again with --autosubmit changes it.
        TEXT

      # The question.
      QUESTION = "Send replay records? [y/N] "

      # Where the answer is kept.
      getter path : Path

      def initialize(root : Path)
        @path = root / FILE
      end

      # The answer on file, or `nil` when there is none.
      def answer : Bool?
        word = File.read(@path).split.first?
        return if word.nil?

        word == "yes"
      rescue File::Error
        nil
      end

      # Writes *agreed* down.
      def record(agreed : Bool) : Nil
        Dir.mkdir_p @path.parent
        File.write @path, "#{agreed ? "yes" : "no"} #{Time.utc.to_rfc3339}\n"
      end

      # Prints the text, asks the question, and keeps the answer.
      #
      # Anything but `y` or `yes` is no, so an Enter alone declines.
      def ask(input : IO, output : IO) : Bool
        output.puts TEXT % @path
        output.puts
        output.print QUESTION
        output.flush

        word = (input.gets || "").strip.downcase
        agreed = word == "y" || word == "yes"
        output.puts agreed ? "Thank you. Records will be sent when the game exits." : "Nothing will be sent."
        output.puts
        record agreed
        agreed
      end
    end
  end
end
