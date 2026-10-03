require "http/server"
require "../spec_helper"

Spectator.describe Roguelike::Update do
  alias Update = Roguelike::Update

  # A directory nothing else writes to.
  def root : Path
    made = Path[File.tempname "roguelike-update", nil]
    Dir.mkdir_p made
    made
  end

  describe ".newer?" do
    it "orders by the three numbers" do
      expect(Update.newer? "0.2.2", "0.2.1").to be_true
      expect(Update.newer? "0.3.0", "0.2.9").to be_true
      expect(Update.newer? "1.0.0", "0.99.99").to be_true
      expect(Update.newer? "0.2.1", "0.2.1").to be_false
      expect(Update.newer? "0.2.0", "0.2.1").to be_false
      expect(Update.newer? "0.10.0", "0.9.0").to be_true
    end

    it "treats anything that is not X.Y.Z as not newer" do
      expect(Update.newer? "0.3.0-rc1", "0.2.1").to be_false
      expect(Update.newer? "0.3.0", "0.2.1+g1234").to be_false
      expect(Update.newer? "latest", "0.2.1").to be_false
    end
  end

  describe ".notice" do
    it "says where the newer release is" do
      found = Update::Release.new "0.9.0", "https://example.test/v0.9.0", Time.utc
      line = Update.notice("0.2.1", root) { found }
      expect(line).to eq("crystal-roguelike 0.9.0 is out: https://example.test/v0.9.0")
    end

    it "says nothing when this build is as new or newer" do
      found = Update::Release.new "0.2.1", "https://example.test/v0.2.1", Time.utc
      expect(Update.notice("0.2.1", root) { found }).to be_nil
      expect(Update.notice("0.3.0", root) { found }).to be_nil
    end

    it "says nothing when nothing answers" do
      expect(Update.notice("0.2.1", root) { nil }).to be_nil
    end

    it "keeps the answer for a day and asks again after" do
      where = root
      asked = 0
      now = Time.utc 2026, 10, 3, 12
      fetch = -> { asked += 1; Update::Release.new "0.9.0", "https://example.test/v0.9.0", now }

      Update.notice("0.2.1", where, now, &fetch)
      Update.notice("0.2.1", where, now + 23.hours, &fetch)
      expect(asked).to eq(1)

      Update.notice("0.2.1", where, now + 25.hours, &fetch)
      expect(asked).to eq(2)
    end

    it "does not cache a failure" do
      where = root
      asked = 0
      Update.notice("0.2.1", where) { asked += 1; nil }
      Update.notice("0.2.1", where) { asked += 1; nil }
      expect(asked).to eq(2)
    end
  end

  describe ".fetch" do
    it "reads the tag and the page from GitHub's answer" do
      server = HTTP::Server.new do |context|
        context.response.content_type = "application/json"
        context.response.print %({"tag_name": "v0.4.0", "html_url": "https://example.test/releases/tag/v0.4.0", "name": "0.4.0"})
      end
      port = server.bind_tcp("127.0.0.1", 0).port
      spawn { server.listen }

      begin
        found = Update.fetch Time.utc, "http://127.0.0.1:#{port}/latest"
        expect(found.try(&.version)).to eq("0.4.0")
        expect(found.try(&.url)).to eq("https://example.test/releases/tag/v0.4.0")
      ensure
        server.close
      end
    end

    it "is nil for an error answer and for nothing listening" do
      server = HTTP::Server.new do |context|
        context.response.status_code = 403
        context.response.print "no"
      end
      port = server.bind_tcp("127.0.0.1", 0).port
      spawn { server.listen }

      begin
        expect(Update.fetch Time.utc, "http://127.0.0.1:#{port}/latest").to be_nil
      ensure
        server.close
      end

      expect(Update.fetch Time.utc, "http://127.0.0.1:9/latest").to be_nil
    end
  end
end
