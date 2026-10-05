require "http/client"
require "openssl"
require "../roguelike"

module Roguelike
  # Whether a newer release of the game is out.
  #
  # The game asks GitHub for its latest release when it starts, at most once
  # a day, and keeps the answer in the state directory between runs. When the
  # latest release is newer than this binary, one line says so and gives the
  # release's address.
  #
  # The check is quiet about everything else. A binary that is ahead of the
  # latest release is a build of unreleased work, and it hears nothing. A
  # network that does not answer within a few seconds is left alone until
  # the next day.
  module Update
    # The repository the releases are cut from.
    REPOSITORY = "plambert/crystal-roguelike.cr"

    # Where GitHub says what the latest release is.
    LATEST = "https://api.github.com/repos/#{REPOSITORY}/releases/latest"

    # How long an answer is kept before GitHub is asked again.
    DAILY = 24.hours

    # How long to wait to connect, and for the answer.
    WAIT = 3.seconds

    # What the cached answer is called under the game's state directory.
    FILE = "latest-release"

    # A release GitHub told us about.
    record Release, version : String, url : String, checked_at : Time do
      include JSON::Serializable
    end

    # What GitHub answers with. Only two fields matter.
    private class Answer
      include JSON::Serializable

      getter tag_name : String
      getter html_url : String
    end

    # The line to show when a newer release is out than *current*, or `nil`.
    #
    # *root* is the state directory the answer is cached in. *fetch* is what
    # asks GitHub, replaced in a spec.
    def self.notice(current : String = VERSION, root : Path = Submit.root,
                    now : Time = Time.utc, &fetch : -> Release?) : String?
      latest = cached(root, now) || fetch.call.try { |found| remember root, found }
      return unless latest
      return unless newer? latest.version, current

      "crystal-roguelike #{latest.version} is out: #{latest.url}"
    end

    # :ditto:
    def self.notice(current : String = VERSION, root : Path = Submit.root,
                    now : Time = Time.utc) : String?
      notice(current, root, now) { fetch now }
    end

    # Whether *candidate* is a later version than *current*.
    #
    # Both are read as `X.Y.Z`. Anything that does not read that way is not
    # newer than anything, so a version with a suffix never prompts.
    def self.newer?(candidate : String, current : String) : Bool
      later = parts candidate
      mine = parts current
      return false unless later && mine

      later > mine
    end

    # The three numbers in *version*, or `nil` for a string that is not one.
    private def self.parts(version : String) : {Int32, Int32, Int32}?
      match = version.match /\A(\d+)\.(\d+)\.(\d+)\z/
      return unless match

      {match[1].to_i, match[2].to_i, match[3].to_i}
    end

    # The answer kept from a check less than a day before *now*, or `nil`.
    def self.cached(root : Path, now : Time) : Release?
      kept = Release.from_json File.read(root / FILE)
      return if now - kept.checked_at > DAILY

      kept
    rescue File::Error | JSON::Error
      nil
    end

    # Keeps *release* for the next day of runs. Answers it.
    def self.remember(root : Path, release : Release) : Release
      Dir.mkdir_p root
      File.write root / FILE, release.to_json
      release
    rescue File::Error
      release
    end

    # Asks GitHub, from *url*. Answers `nil` for anything but a good answer.
    def self.fetch(now : Time = Time.utc, url : String = LATEST) : Release?
      uri = URI.parse url
      headers = HTTP::Headers{
        "Accept"     => "application/vnd.github+json",
        "User-Agent" => "crystal-roguelike/#{VERSION}",
      }

      response = Tls.client uri do |http|
        http.connect_timeout = WAIT
        http.read_timeout = WAIT
        http.write_timeout = WAIT
        http.get uri.request_target, headers
      end
      return unless response.status.success?

      answer = Answer.from_json response.body
      Release.new answer.tag_name.lchop('v'), answer.html_url, now
    rescue IO::Error | OpenSSL::Error | JSON::Error | URI::Error
      nil
    end
  end
end
