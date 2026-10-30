require "file_utils"
require "spectator"
require "../src/crystal-roguelike"
require "./support/fixture"
require "./support/headless"
require "./support/playing"

# The suite keeps its state in a directory of its own, so nothing a spec
# does reaches the player's options, saves or logs. `Save.state_home` reads
# the variable on every call and checks it before `LOCALAPPDATA` on Windows.
SPEC_STATE_HOME = Path[Dir.tempdir, "roguelike-spec-state-#{Process.pid}-#{Random::Secure.hex(4)}"].to_s
Dir.mkdir_p SPEC_STATE_HOME
ENV["XDG_STATE_HOME"] = SPEC_STATE_HOME

# Spectator runs the suite from its own `at_exit`, which would run after a
# handler registered here, so the directory goes in an after-suite hook.
Spectator.configure do |config|
  config.after_suite { FileUtils.rm_rf SPEC_STATE_HOME }
end
