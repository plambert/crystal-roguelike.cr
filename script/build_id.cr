# Prints the commit a binary is being built from.
#
#     crystal run script/build_id.cr -- [DIRECTORY]
#
# The short hash, with a "+" after it when a tracked file differs from what
# that commit holds. "unknown" when there is no repository to ask, which is
# what a build from a release tarball gets.
#
# Untracked files are not counted. Nothing untracked reaches the binary
# unless a tracked file was edited to require it, and counting them would
# mark every working tree with a stray note in it.
#
# Another shard that depends on this one holds it under its own `lib/`, with
# no repository of its own. The nearest repository above it is the other
# shard's, so its commit would be the wrong answer. `lib/.shards.info` names
# the commit that `shards install` checked out, and that is the answer there.
#
# `src/roguelike/version.cr` runs this with the `run` macro while the
# compiler expands its macros. It is Crystal rather than a shell script so
# that one program answers on every platform, Windows included, where a
# macro's command runs with no shell to read one.
#
# Nothing here raises. Any question that cannot be asked is answered
# "unknown", because a build must not fail for want of a stamp. Nor does it
# use a regular expression: that would link PCRE2 into a program every build
# compiles, and a machine without its development files could not build.

module BuildId
  UNKNOWN = "unknown"

  # The directory holding shard.yml, with every symbolic link resolved.
  def self.root : String?
    File.realpath File.join(__DIR__, "..")
  rescue File::Error
    nil
  end

  # Runs git in *directory*, and answers its output, or nil when git is
  # missing or fails.
  def self.git(directory : String, *args : String) : String?
    output = IO::Memory.new
    status = Process.run "git", args.to_a, chdir: directory, output: output, error: Process::Redirect::Close
    status.success? ? output.to_s.strip : nil
  rescue File::Error | IO::Error
    nil
  end

  # The commit of the repository at *root*, when *directory* is inside that
  # repository and not some other one above it.
  def self.from_repository(root : String, directory : String) : String?
    top = git directory, "rev-parse", "--show-toplevel"
    return if top.nil? || top.empty?
    return unless (File.realpath(top) rescue nil) == root

    commit = git directory, "rev-parse", "--short", "HEAD"
    return UNKNOWN if commit.nil? || commit.empty?

    changes = git directory, "status", "--porcelain", "--untracked-files=no"
    changes.nil? || changes.empty? ? commit : "#{commit}+"
  end

  # The commit `shards install` checked out, from the `lib/.shards.info` of
  # the shard that depends on this one.
  def self.from_shards_info(root : String) : String?
    name = File.read_lines(File.join(root, "shard.yml"))
      .find(&.starts_with?("name:"))
      .try(&.lchop("name:").strip)
    return if name.nil? || name.empty?

    info = File.join(root, "..", ".shards.info")
    return unless File.file? info

    found = false
    File.each_line info do |line|
      if line == "  #{name}:"
        found = true
      elsif found && line.starts_with?("  ") && !line.starts_with?("   ")
        break
      elsif found && line.includes?("version:") && (at = line.index("git.commit."))
        hash = line[(at + "git.commit.".size)..].each_char.take_while(&.hex?).join
        return hash[0, 7] unless hash.empty?
      end
    end
    nil
  rescue File::Error | IO::Error
    nil
  end

  def self.answer(directory : String) : String
    root = self.root
    return UNKNOWN unless root && Dir.exists?(directory)

    from_repository(root, directory) || from_shards_info(root) || UNKNOWN
  end
end

print BuildId.answer(ARGV.first? || ".")
