require "../spec_helper"

Spectator.describe Roguelike::Tls do
  alias Tls = Roguelike::Tls

  describe ".bundle" do
    it "leaves the default alone when the person named a bundle" do
      expect(Tls.bundle({"SSL_CERT_FILE" => "/somewhere/cert.pem"})).to be_nil
      expect(Tls.bundle({"SSL_CERT_DIR" => "/somewhere/certs"})).to be_nil
    end

    it "treats an empty override as unset" do
      found = Tls.bundle({"SSL_CERT_FILE" => ""})
      {% if flag?(:darwin) %}
        expect(found).to eq(Tls::SYSTEM_BUNDLE)
      {% else %}
        expect(found).to be_nil
      {% end %}
    end

    it "reads Apple's bundle on macOS and the library's default elsewhere" do
      found = Tls.bundle({} of String => String)
      {% if flag?(:darwin) %}
        expect(found).to eq("/etc/ssl/cert.pem")
        expect(File.exists? found.not_nil!).to be_true
      {% else %}
        expect(found).to be_nil
      {% end %}
    end
  end

  describe ".context" do
    it "is a client context that verifies the peer" do
      context = Tls.context
      expect(context).to be_a(OpenSSL::SSL::Context::Client)
      expect(context.verify_mode).to eq(OpenSSL::SSL::VerifyMode::PEER)
    end
  end

  describe ".client" do
    it "gives a plain client for http and closes it after" do
      kept = nil.as(HTTP::Client?)
      answer = Tls.client(URI.parse "http://127.0.0.1:9/") do |http|
        kept = http
        42
      end
      expect(answer).to eq(42)
      expect(kept.try(&.tls?)).to be_nil
    end

    it "gives a TLS client for https" do
      Tls.client(URI.parse "https://example.test/") do |http|
        expect(http.tls?).to be_a(OpenSSL::SSL::Context::Client)
      end
    end
  end
end
