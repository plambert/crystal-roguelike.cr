require "json"

# Lets `script/spec-parallel` run one spec binary as several processes.
#
# `ROGUELIKE_SPEC_SHARD` is `I/N`, and the process runs only shard I of N.
# `ROGUELIKE_SPEC_PLAN` names a file of `SHARD<TAB>PATH` lines that puts each
# spec file in a shard, with paths from the project root. An example in a
# file the plan does not name goes to a shard chosen from the file's path. So
# every example lands in exactly one shard.
#
# `ROGUELIKE_SPEC_REPORT` names a JSON file. The process writes its counts,
# its failed locations and the seconds each spec file took there when it ends.
module SpecParallel
  ROOT = Path[__DIR__].parent.parent

  # The path from the project root of the file *example* is in.
  def self.file(example : Spectator::Example) : String
    return "" unless location = example.location?
    Path[location.file].relative_to(ROOT).to_posix.to_s
  end

  # Drops every example outside this process's shard.
  class Reject < Spectator::NodeFilter
    def initialize(@shard : Int32, @count : Int32, @plan : Hash(String, Int32))
    end

    def includes?(node) : Bool
      return false unless node.is_a?(Spectator::Example)
      file = SpecParallel.file(node)
      shard = @plan.fetch(file) { file.bytes.sum(0) % @count }
      shard != @shard
    end
  end

  # Records the counts and each file's time, and writes them at the end.
  class Report < Spectator::Formatting::Formatter
    @seconds = Hash(String, Float64).new(0.0)
    @mark = Time.instant

    def initialize(@path : String)
    end

    # The time since the last mark goes to the example starting or finishing,
    # which charges a group's setup to the file the group is in.
    private def charge(notification)
      now = Time.instant
      @seconds[SpecParallel.file(notification.example)] += (now - @mark).total_seconds
      @mark = now
    end

    def start(notification)
      @mark = Time.instant
    end

    def example_started(notification)
      charge notification
    end

    def example_finished(notification)
      charge notification
    end

    def dump_summary(notification)
      report = notification.report
      counts = report.counts
      failed = report.failures.compact_map(&.location?).map(&.to_s)
      File.write @path, {
        examples:  counts.run,
        failures:  counts.fail,
        errors:    counts.error,
        pending:   counts.pending,
        remaining: counts.remaining,
        failed:    failed,
        seconds:   @seconds,
      }.to_json
    end
  end

  def self.configure(config) : Nil
    if path = ENV["ROGUELIKE_SPEC_REPORT"]?
      config.add_formatter Report.new(path)
    end

    return unless shard = ENV["ROGUELIKE_SPEC_SHARD"]?
    index, count = shard.split('/', 2).map(&.to_i)
    plan = {} of String => Int32
    if source = ENV["ROGUELIKE_SPEC_PLAN"]?
      File.each_line(source) do |line|
        number, file = line.split('\t', 2)
        plan[file] = number.to_i
      end
    end
    config.add_node_reject Reject.new(index, count, plan)
  end
end

Spectator.configure { |config| SpecParallel.configure config }
