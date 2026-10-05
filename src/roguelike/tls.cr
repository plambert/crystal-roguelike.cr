require "http/client"
require "openssl"
require "../roguelike"

module Roguelike
  # The TLS settings every HTTPS connection the game opens is made with.
  #
  # OpenSSL looks for its certificate bundle in the directory compiled into
  # the library. A macOS binary links Homebrew's OpenSSL from its archive,
  # and that directory is Homebrew's, which a Mac without Homebrew does not
  # have. Apple keeps a bundle of its own at `/etc/ssl/cert.pem` on every
  # Mac, so on macOS the game reads that one. `SSL_CERT_FILE` and
  # `SSL_CERT_DIR` still win when they are set, since OpenSSL honours them
  # and a person who set one meant it.
  #
  # Linux builds are left on the library's default, which is `/etc/ssl/certs`
  # on the Alpine the static binaries are built against and present on every
  # distribution.
  module Tls
    # Apple's bundle, on every Mac.
    SYSTEM_BUNDLE = "/etc/ssl/cert.pem"

    # The variables OpenSSL reads for a bundle of the person's own.
    OVERRIDES = %w[SSL_CERT_FILE SSL_CERT_DIR]

    # A client context, with the bundle `.bundle` names when it names one.
    def self.context : OpenSSL::SSL::Context::Client
      context = OpenSSL::SSL::Context::Client.new
      bundle.try { |file| context.ca_certificates = file }
      context
    end

    # The bundle to read instead of the library's default, or `nil` to leave
    # the default alone.
    def self.bundle(env : Hash(String, String) = ENV.to_h) : String?
      return if OVERRIDES.any? { |name| env[name]?.presence }

      {% if flag?(:darwin) %}
        return SYSTEM_BUNDLE if File.exists? SYSTEM_BUNDLE
      {% end %}

      nil
    end

    # Runs *block* with a client for *uri*, closed afterwards. An `https`
    # address gets `.context`; anything else gets a plain client.
    def self.client(uri : URI, & : HTTP::Client -> T) : T forall T
      http = uri.scheme == "https" ? HTTP::Client.new(uri, tls: context) : HTTP::Client.new(uri)
      begin
        yield http
      ensure
        http.close
      end
    end
  end
end
