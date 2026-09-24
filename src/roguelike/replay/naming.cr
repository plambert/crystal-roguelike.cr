module Roguelike
  module Replay
    # Where `--replay-log` writes.
    #
    # The argument is a pattern rather than a name, so that one spelling
    # records every run a person plays. Three things go in it.
    #
    # * `%s` is the character's name as a slug. `Save.slug` makes it, so it is
    #   the name the save file is under.
    # * `%d` is a number that rises until the name is free. `%02d` pads it to
    #   two digits with zeros, and any other width works the same way.
    # * `%%` is one per cent sign.
    #
    # A pattern that names a directory that exists takes the name
    # `bots/PROTOCOL.md` section 3.2 asks for inside it, which is
    # `<started_at>_<seed>_<player>.jsonl`.
    #
    # A pattern with no `%d` in it is used as it stands, and an old file of
    # that name is written over. A person who passed one name asked for one
    # file.
    module Naming
      # What goes in the name of a character who has none.
      NOBODY = "nobody"

      # How the time goes in the name a directory takes.
      #
      # `2026-09-23T18:04:11Z` has colons in it. A colon is a path separator
      # on some systems and a nuisance to type on the rest, so the compact
      # form of the same instant is used.
      STAMP = "%Y%m%dT%H%M%SZ"

      # What the file is called.
      SUFFIX = ".jsonl"

      # Where a run by *player* on *seed*, started at *started*, is written.
      def self.resolve(pattern : String, player : String, seed : UInt64,
                       started : Time) : Path
        return free directory(pattern, player, seed, started) if Dir.exists? pattern

        slug = Save.slug player
        slug = NOBODY if slug.empty?
        return Path[fill pattern, slug, 1] unless indexed? pattern

        index = 1
        loop do
          found = Path[fill pattern, slug, index]
          return found unless File.exists? found

          index += 1
        end
      end

      # The name a directory takes, which the spec spells out.
      private def self.directory(pattern : String, player : String,
                                 seed : UInt64, started : Time) : Path
        slug = Save.slug player
        slug = NOBODY if slug.empty?

        Path[pattern] / "#{started.to_utc.to_s STAMP}_#{seed}_#{slug}#{SUFFIX}"
      end

      # *wanted*, or the first name beside it that no file has.
      private def self.free(wanted : Path) : Path
        return wanted unless File.exists? wanted

        stem = wanted.to_s.rchop SUFFIX
        index = 2
        loop do
          found = Path["#{stem}-#{index}#{SUFFIX}"]
          return found unless File.exists? found

          index += 1
        end
      end

      # What this module reads in a pattern.
      PLACEHOLDER = /%(%|s|\d*d)/

      # *pattern* with its placeholders filled in.
      def self.fill(pattern : String, slug : String, index : Int32) : String
        pattern.gsub PLACEHOLDER do |found|
          case body = found[1..]
          when "%" then "%"
          when "s" then slug
          else          numbered body, index
          end
        end
      end

      # Whether *pattern* has a number in it.
      def self.indexed?(pattern : String) : Bool
        pattern.scan(PLACEHOLDER).any? &.[1].ends_with?('d')
      end

      # *index* as *body* asks for it, where *body* is the `02d` of `%02d`.
      #
      # A width pads with zeros whether or not the zero was written. A name
      # padded with spaces is not what anybody wants a file called.
      private def self.numbered(body : String, index : Int32) : String
        width = body.rchop.to_i? || 0

        index.to_s.rjust width, '0'
      end
    end
  end
end
