# Text a spec compares against. It lives in a file so that a change shows as a
# diff.
#
# A rendered screen goes here. So does a field of view. So does a generated
# level. Each of those is worth asserting whole. An inline heredoc would bury
# the spec around it. A file lets `git diff` show what moved.
module Fixture
  # Where the files live.
  DIRECTORY = Path[__DIR__].parent / "fixtures"

  # The fixture named *name*.
  #
  # Set `UPDATE_FIXTURES` in the environment and this method writes *actual*
  # to the file first. It then returns what it wrote. That is how a fixture is
  # regenerated after a deliberate change:
  #
  #     UPDATE_FIXTURES=1 crystal spec
  #
  # Read the diff before committing a regenerated fixture. A fixture
  # regenerated to make a red spec green asserts nothing.
  def self.expected(name : String, actual : String) : String
    path = DIRECTORY / name

    if ENV.has_key? "UPDATE_FIXTURES"
      Dir.mkdir_p path.dirname.to_s
      File.write path, "#{actual}\n"
    end

    unless File.exists? path
      raise "no fixture at #{path}: run UPDATE_FIXTURES=1 crystal spec to write one"
    end

    # Exactly one trailing newline comes off. That newline is the file's
    # terminator. It is not content. Chomping more would throw away the blank
    # rows at the bottom of a screen. Those rows say a pane is the height it
    # claims.
    stored = File.read path
    stored.ends_with?('\n') ? stored[0...-1] : stored
  end
end
