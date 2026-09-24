require "./replay/streams"
require "./replay/lines"
require "./replay/naming"
require "./replay/reading"
require "./replay/verifier"
require "./replay/log"

module Roguelike
  # A run written down, and a run read back.
  #
  # `--replay-log PATH` records every run this process plays. The file is
  # JSON Lines, which `bots/PROTOCOL.md` section 3 describes. `Replay::Log`
  # writes it and `Replay::Verifier` checks it.
  #
  # A replay holds the seed and the actions. It does not hold the run. The
  # game is a function of the seed and the actions, so playing them again
  # rebuilds every state the run passed through. That is what makes the file
  # small, and it is also what makes the check worth something: a rebuild
  # that differs says the build changed under the replay.
  module Replay
  end
end
