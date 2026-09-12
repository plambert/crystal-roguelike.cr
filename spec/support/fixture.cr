# Text a spec compares against, kept in a file so a change shows as a diff.
#
# A rendered screen, a field of view, a generated level: things where the
# assertion worth making is "all of this, exactly", and where an inline
# heredoc would bury the spec. Keeping them in files means `git diff` shows
# what moved.
module Fixture
  # Where the files live.
  DIRECTORY = Path[__DIR__].parent / "fixtures"

  # The fixture named *name*.
  #
  # With `UPDATE_FIXTURES` set in the environment, *actual* is written there
  # first and comes straight back, which is how a fixture is regenerated after
  # a deliberate change:
  #
  #     UPDATE_FIXTURES=1 crystal spec
  #
  # Read the diff before committing one. A fixture that is regenerated to make
  # a red spec green asserts nothing.
  def self.expected(name : String, actual : String) : String
    path = DIRECTORY / name

    if ENV.has_key? "UPDATE_FIXTURES"
      Dir.mkdir_p path.dirname.to_s
      File.write path, "#{actual}\n"
    end

    unless File.exists? path
      raise "no fixture at #{path}: run UPDATE_FIXTURES=1 crystal spec to write one"
    end

    # Exactly one trailing newline comes off, because it is the file's
    # terminator rather than content. Chomping more would throw away the blank
    # rows at the bottom of a screen, which are the ones that say a pane is
    # the height it claims.
    stored = File.read path
    stored.ends_with?('\n') ? stored[0...-1] : stored
  end
end
