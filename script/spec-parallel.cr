# Runs the spec suite as several processes and reports one result.
#
#     script/spec-parallel [-j N] [--save-times] [COMPILER ARG...] [SPEC FILE...] [-- RUNTIME ARG...]
#
# The suite is compiled once. The binary then runs once per shard, each run
# selecting its examples through `spec/support/parallel.cr`. Shards are
# balanced by the seconds each spec file took, read from
# `script/spec-times.tsv`. A file missing from the table counts as the median.
# The files in `SERIAL` run alone, in a last shard that starts when the
# others have finished.
#
# Each shard gets its own temporary directory and state directory. Its output
# goes to a log, and the combined failures, pending examples and counts are
# printed at the end. The exit status is 1 when any example failed or any
# shard did not finish.
#
# Arguments before `--` go to `crystal build`, except paths ending in `.cr`
# and directories, which select spec files the way `crystal spec` does.
# Arguments after `--` go to every shard.
#
# `-j N` sets the number of shards. It defaults to the number of CPUs.
# `--save-times` writes the seconds of every file that ran into the table.
# Run it with `-j 1` on a quiet machine, so the times are not inflated by
# shards competing for the CPU.
# `--no-build` runs the binary the last run compiled, as it is.
# `--keep` keeps each shard's output, plan and report, and says where.

require "file_utils"
require "json"

ROOT     = Path[__DIR__].parent
TIMES    = ROOT / "script" / "spec-times.tsv"
FAILURES = ROOT / ".spectator-failures"

# Spec files that cannot share the machine with other shards.
SERIAL = [] of String

class Shard
  getter index : Int32
  getter files : Array(String)
  property log = ""
  property status : Process::Status? = nil
  property report : JSON::Any? = nil
  property elapsed = Time::Span.zero

  def initialize(@index, @files)
  end

  def label(count) : String
    index == count ? "serial" : "#{index + 1}/#{count}"
  end
end

def usage(message) : NoReturn
  STDERR.puts "spec-parallel: #{message}"
  exit 2
end

jobs = System.cpu_count.to_i
save_times = false
build = true
keep = false
compiler_args = [] of String
runtime_args = [] of String
selected = [] of String

arguments = ARGV.dup
until arguments.empty?
  argument = arguments.shift
  case argument
  when "--"
    runtime_args.concat arguments
    arguments.clear
  when "-j", "--jobs"
    jobs = arguments.shift?.try(&.to_i?) || usage("#{argument} needs a number")
  when /\A(?:-j|--jobs=)(\d+)\z/
    jobs = $1.to_i
  when "--save-times"
    save_times = true
  when "--no-build"
    build = false
  when "--keep"
    keep = true
  when /\.cr\z/
    usage "no file #{argument}" unless File.file?(argument)
    selected << Path[argument].expand.relative_to(ROOT).to_posix.to_s
  else
    if Dir.exists?(argument)
      Dir["#{Path[argument].to_posix}/**/*_spec.cr"].each do |file|
        selected << Path[file].expand.relative_to(ROOT).to_posix.to_s
      end
    else
      compiler_args << argument
    end
  end
end
usage "-j must be at least 1" if jobs < 1

Dir.cd ROOT
files = (selected.empty? ? Dir["spec/**/*_spec.cr"] : selected).map { |file| Path[file].to_posix.to_s }.uniq!.sort!

# Seconds per file from the table.
times = {} of String => Float64
if File.exists?(TIMES)
  File.each_line(TIMES) do |line|
    next if line.blank? || line.starts_with?('#')
    seconds, file = line.split('\t', 2)
    times[file] = seconds.to_f
  end
end
known = times.values.sort!
median = known.empty? ? 1.0 : known[known.size // 2]

# Longest files first, each to the shard with the least so far. The suite
# cannot finish sooner than its slowest file.
loads = Array.new(jobs, 0.0)
members = Array.new(jobs) { [] of String }
(files - SERIAL).sort_by { |file| {-times.fetch(file, median), file} }.each do |file|
  least = loads.index!(loads.min)
  loads[least] += times.fetch(file, median)
  members[least] << file
end
shards = members.map_with_index { |list, index| Shard.new(index, list) }
serial = files & SERIAL
shards << Shard.new(jobs, serial) unless serial.empty?

work = Path[Dir.tempdir] / "roguelike-spec-parallel-#{Process.pid}"
Dir.mkdir_p work
at_exit { keep ? STDERR.puts("Shard output is in #{work}") : FileUtils.rm_rf(work.to_s) }

plan = work / "plan.tsv"
File.open(plan, "w") do |io|
  shards.each { |shard| shard.files.each { |file| io << shard.index << '\t' << file << '\n' } }
end

# The binary sits at a fixed path so the compiler cache serves the next build.
Dir.mkdir_p "bin"
binary = Path["bin", "spec-parallel-suite"].expand.to_s
binary += ".exe" if {{ flag?(:win32) }}
entry = files.join('\n') { |file| %(require "./#{file}") }

compiled = Time.measure do
  if build
    STDERR.puts "Compiling #{files.size} spec files"
    built = Process.run ENV.fetch("CRYSTAL", "crystal"),
      ["build", "--stdin-filename", "spec-parallel-entry.cr", "-o", binary] + compiler_args,
      input: IO::Memory.new(entry), output: :inherit, error: :inherit
    exit 1 unless built.success?
  else
    usage "no #{binary} to run" unless File.exists?(binary)
  end
end
STDERR.puts "Compiled in #{compiled.total_seconds.round(1)}s, running #{shards.size} shards"

def run(shard : Shard, binary, plan, work, runtime_args, count) : Nil
  home = work / "shard-#{shard.index}"
  temp = home / "tmp"
  Dir.mkdir_p temp
  Dir.mkdir_p home / "state"
  shard.log = (home / "output.log").to_s
  report = home / "report.json"
  environment = {
    "ROGUELIKE_SPEC_SHARD"  => "#{shard.index}/#{count}",
    "ROGUELIKE_SPEC_PLAN"   => plan.to_s,
    "ROGUELIKE_SPEC_REPORT" => report.to_s,
    "XDG_STATE_HOME"        => (home / "state").to_s,
    "TMPDIR"                => temp.to_s,
    "TMP"                   => temp.to_s,
    "TEMP"                  => temp.to_s,
  }
  began = Time.instant
  File.open(shard.log, "w") do |log|
    shard.status = Process.run binary, runtime_args, env: environment, output: log, error: log
  end
  shard.elapsed = Time.instant - began
  shard.report = JSON.parse(File.read(report)) if File.exists?(report)
end

# The parallel shards together, then the serial one.
def run_shards(shards, binary, plan, work, runtime_args, count) : Nil
  finished = Channel(Shard).new
  concurrent = shards.reject { |shard| shard.index == count }
  concurrent.each do |shard|
    spawn do
      run shard, binary, plan, work, runtime_args, count
      finished.send shard
    end
  end
  concurrent.size.times { done finished.receive, count }
  shards.select { |shard| shard.index == count }.each do |shard|
    run shard, binary, plan, work, runtime_args, count
    done shard, count
  end
end

def done(shard, count) : Nil
  report = shard.report
  said = report ? "#{report["examples"]} examples, #{report["failures"]} failures" : "no report"
  STDERR.puts "  shard #{shard.label(count)}: #{said} in #{shard.elapsed.total_seconds.round(1)}s"
end

running = Time.instant
run_shards shards, binary, plan, work, runtime_args, jobs
wall = Time.instant - running

def describe(status : Process::Status?) : String
  return "not run" unless status
  status.normal_exit? ? "exit #{status.exit_code}" : status.to_s
end

# A numbered block from one shard, renumbered to follow the blocks before it.
def blocks(text : String, heading : String, after : Int32) : {String, Int32}
  start = text.index("\n#{heading}\n")
  return {"", after} unless start
  rest = text[(start + heading.size + 2)..]
  stop = ["\nPending:\n", "\nFailures:\n", "\nFinished in "].compact_map { |marker| rest.index(marker) }.min? || rest.size
  section = rest[0, stop]
  highest = after
  renumbered = section.gsub(/^(\s*)(\d+)((?:\.\d+)?\) )/m) do
    number = $2.to_i + after
    highest = Math.max(highest, number)
    "#{$1}#{number}#{$3}"
  end
  {renumbered.strip('\n'), highest}
end

totals = Hash(String, Int64).new(0_i64)
failed_locations = [] of String
pending_text = [] of String
failure_text = [] of String
commands = [] of String
broken = [] of Shard
pending_count = 0
failure_count = 0

shards.each do |shard|
  text = File.exists?(shard.log) ? File.read(shard.log) : ""
  report = shard.report
  unless report && (status = shard.status) && (status.success? || report["failures"].as_i > 0)
    broken << shard
  end
  next unless report
  %w[examples failures errors pending remaining].each { |key| totals[key] += report[key].as_i64 }
  report["failed"].as_a.each { |location| failed_locations << location.as_s }

  section, pending_count = blocks(text, "Pending:", pending_count)
  pending_text << section unless section.empty?
  section, failure_count = blocks(text, "Failures:", failure_count)
  failure_text << section unless section.empty?
  if start = text.index("\nFailed examples:\n")
    text[start..].each_line { |line| commands << line if line.starts_with?("crystal spec ") }
  end
end

unless pending_text.empty?
  puts "\nPending:\n\n#{pending_text.join("\n\n")}"
end
unless failure_text.empty?
  puts "\nFailures:\n\n#{failure_text.join("\n\n")}"
end
broken.each do |shard|
  lines = File.exists?(shard.log) ? File.read_lines(shard.log) : [] of String
  puts "\nShard #{shard.label(jobs)} did not finish (#{describe shard.status}). " \
       "The end of its output:\n\n#{lines.last(40).join('\n')}"
end

slowest = shards.max_by?(&.elapsed)
puts
puts "Finished in #{wall.total_seconds.round(2)}s with #{shards.size} shards " \
     "(compile #{compiled.total_seconds.round(1)}s, slowest shard #{slowest.try(&.elapsed.total_seconds.round(1))}s)"
line = "#{totals["examples"]} examples, #{totals["failures"]} failures"
line += " (#{totals["errors"]} errors)" if totals["errors"] > 0
line += ", #{totals["pending"]} pending" if totals["pending"] > 0
line += ", #{totals["remaining"]} not run" if totals["remaining"] > 0
puts line
puts "#{broken.size} shards did not finish" unless broken.empty?
unless commands.empty?
  puts "\nFailed examples:\n\n#{commands.join('\n')}"
end

File.write FAILURES, failed_locations.join { |location| "#{location}\n" }

# A run of the whole suite replaces the table, so deleted files leave it.
if save_times
  if selected.empty?
    times.clear
  else
    times.reject! { |file, _| files.includes?(file) }
  end
  shards.each do |shard|
    shard.report.try &.["seconds"].as_h.each { |file, seconds| times[file] = seconds.as_f.round(3) }
  end
  File.open(TIMES, "w") do |io|
    io.puts "# Seconds each spec file takes, read by script/spec-parallel."
    io.puts "# Refresh with script/spec-parallel --save-times."
    times.keys.sort!.each { |file| io << times[file] << '\t' << file << '\n' }
  end
end

exit 1 unless broken.empty? && totals["failures"] == 0 && totals["remaining"] == 0
