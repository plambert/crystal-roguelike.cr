require "../spec_helper"

# The game itself, played in a Windows pseudoconsole this spec plays the
# terminal for: Windows Terminal and WezTerm host it in the same kind of
# console. A run is begun, walked, and left, with nothing saved and no window
# opened.
{% skip_file unless flag?(:win32) %}

require "file_utils"
require "termbuf-input/win32/pseudo_console"

private module BuiltGame
  # Built once, the first time it is wanted. The compile takes a while.
  def self.path : Path
    @@path ||= build
  end

  @@path : Path? = nil

  private def self.build : Path
    root = Path[__DIR__].parent.parent
    directory = Path[File.tempname "roguelike-conpty", nil]
    Dir.mkdir_p directory
    at_exit { FileUtils.rm_rf directory.to_s }

    built = directory / "crystal-roguelike.exe"
    said = IO::Memory.new
    status = Process.run "crystal", ["build", "--no-debug", "-o", built.to_s, "src/main.cr"],
      output: said, error: said, chdir: root.to_s
    raise "building the game failed:\n#{said}" unless status.success?

    built
  end
end

private def playing(&)
  console = TermBuf::Input::PseudoConsole.new BuiltGame.path.to_s,
    ["--seed", "42", "--no-save", "--no-update-check", "--no-autosubmit"], 120, 40
  begin
    yield console
  ensure
    console.close
  end
end

# Waits up to *timeout* for the console to have shown *text*.
private def shows?(console : TermBuf::Input::PseudoConsole, text : String, timeout = 15.seconds) : Bool
  deadline = Time.instant + timeout
  until Time.instant >= deadline
    return true if console.screen.includes? text
    sleep 50.milliseconds
  end
  false
end

Spectator.describe "the game in a Windows pseudoconsole" do
  it "begins a run, walks, and leaves when asked" do
    playing do |console|
      expect(shows? console, "new character").to be_true

      console.type "a"
      expect(shows? console, "Who is playing?").to be_true

      console.type "\r"
      expect(shows? console, "enters the dungeon").to be_true

      console.type "llll"
      console.type "Q"
      sleep 500.milliseconds
      console.type "y"

      expect(console.wait(15.seconds)).to eq 0
    end
  end
end
