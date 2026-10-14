require "../../src/crystal-roguelike"
require "./scripted"

# Prints a run's fingerprint at every turn, one to a line.
#
# `spec/roguelike/fingerprint_spec.cr` builds this, runs it and compares what
# it printed against the same run played in the spec's own process. A
# fingerprint has to be the same in two processes, and no spec running in one
# can show that. A fork will not do either. Crystal seeds `Object#hash` once
# at startup, and a child inherits the seed its parent was given, so the
# second process has to be a second program.
#
# It takes a mode, a seed, the moves to play for `walk` or the turns for
# `play`, and the name of a fingerprint scheme.

mode = ARGV[0]?
seed = ARGV[1]?.try &.to_u64?
scheme = Roguelike::Fingerprint::Scheme.values.find(&.label.==(ARGV[3]?)) || Scripted::SCHEME

unless mode && seed
  STDERR.puts "usage: fingerprints walk SEED MOVES [SCHEME] | fingerprints play SEED TURNS [SCHEME]"
  exit 2
end

found = case mode
        when "walk" then Scripted.walked seed, ARGV[2]? || Scripted::MOVES, scheme
        when "play" then Scripted.played seed, ARGV[2]?.try(&.to_i) || Scripted::TURNS, scheme
        else             STDERR.puts "no mode called #{mode}"; exit 2
        end

found.each { |line| puts line }
