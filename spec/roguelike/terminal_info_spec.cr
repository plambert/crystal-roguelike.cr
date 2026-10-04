require "../spec_helper"

Spectator.describe TermBuf::TerminalInfo do
  alias Info = TermBuf::TerminalInfo
  alias Screen = Roguelike::Ui::Screen
  alias Capability = TermBuf::Capability
  alias Capabilities = TermBuf::Capabilities

  describe ".gather" do
    it "reports from the environment alone when the streams are not a terminal" do
      env = {"TERM" => "xterm-256color", "COLORTERM" => "truecolor", "HOME" => "/nowhere", "LANG" => "en_US.UTF-8"}
      report = Info.gather IO::Memory.new, IO::Memory.new, env

      expect(report.probed?).to be_false
      expect(report.name).to be_nil
      expect(report.env).to eq({"TERM" => "xterm-256color", "COLORTERM" => "truecolor", "LANG" => "en_US.UTF-8"})
      expect(report.guessed).to contain("Color256")
      expect(report.guessed).to contain("TrueColor")
      expect(report.capabilities).to eq(report.guessed)
      expect(report.size.keys).to eq(["columns", "rows"])
      expect(report.tty.keys).to eq(["stdin", "stdout", "stderr"])
    end

    it "shows what NO_COLOR and a bare TERM do" do
      stripped = Info.gather IO::Memory.new, IO::Memory.new, {"TERM" => "xterm-256color", "NO_COLOR" => "1"}
      expect(stripped.capabilities).not_to contain("Color16")
      expect(stripped.env["NO_COLOR"]).to eq("1")

      bare = Info.gather IO::Memory.new, IO::Memory.new, {"TERM" => "xterm"}
      expect(bare.capabilities).to contain("Color16")
      expect(bare.capabilities).not_to contain("Color256")
    end

    it "is one line of JSON" do
      report = Info.gather IO::Memory.new, IO::Memory.new, {"TERM" => "xterm-256color"}
      text = report.to_json
      expect(text.lines.size).to eq(1)
      expect(JSON.parse(text)["guessed"].as_a).not_to be_empty
      expect(JSON.parse(text)["name"]?).not_to be_nil
      expect(JSON.parse(text)["name"].raw).to be_nil
    end
  end

  describe ".ancestors" do
    it "names the processes above this one, nearest first" do
      found = Info.ancestors
      {% unless flag?(:win32) %}
        expect(found).not_to be_empty
        expect(found.first).not_to be_empty
      {% end %}
    end
  end

  describe "Screen.too_few_colors" do
    it "is nil with 256 colours or more" do
      expect(Screen.too_few_colors Capabilities::XTERM, {} of String => String).to be_nil
      expect(Screen.too_few_colors Capabilities.new(Capability::Color256), {} of String => String).to be_nil
    end

    it "refuses sixteen colours and names what it read" do
      message = Screen.too_few_colors Capabilities::ANSI, {"TERM" => "xterm", "NO_COLOR" => ""}
      expect(message).to contain("requires 256 colours")
      expect(message).to contain("16 colours")
      expect(message).to contain("TERM=xterm")
      expect(message).to contain("NO_COLOR=")
      expect(message).to contain("--dump-terminal-info")
    end

    it "refuses no colour and says when TERM is missing" do
      message = Screen.too_few_colors Capabilities::NONE, {} of String => String
      expect(message).to contain("no colour")
      expect(message).to contain("no TERM")
    end
  end
end
