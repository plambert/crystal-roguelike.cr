require "./theme"
require "./built_in_themes"

module Roguelike::Ui
  # The named theme files in `themes/` under the state directory.
  #
  # Each file holds one theme in the form of `theme.json`, with its `name`
  # key first. The file name comes from the theme's name, so saving a theme
  # under a name it already has writes over its file.
  #
  # The game owns the files of its built-in themes. `.sync` writes each one
  # at startup when it is missing, and writes it again when it differs from
  # the colors in the code. A change made to one of those files is lost the
  # next time the game starts, so a player who wants to change a built-in
  # theme saves it under another name, and `.save` refuses a built-in name.
  module ThemeLibrary
    # The directory under the state root.
    DIRECTORY = "themes"

    # A theme and the name it goes by. *note* says what a built-in theme is
    # for.
    record Named, name : String, theme : Theme, note : String? = nil

    # The game's own themes, in the order the editor lists them.
    BUILT_INS = [
      Named.new("Default", Theme::DEFAULT, "the game's own colors"),
      Named.new("High contrast", Theme::HIGH_CONTRAST, "black ground, bright colors"),
      Named.new("Paper", Theme::PAPER, "dark ink, for a light terminal"),
    ]

    # What went wrong writing the built-in theme files at startup, or `nil`.
    # The theme editor says it once.
    class_property problem : String? = nil

    # The built-in theme whose file a theme called *name* would write over,
    # or `nil` when there is none.
    def self.built_in(name : String) : Named?
      file = file_name name
      BUILT_INS.find { |named| file_name(named.name) == file } if file
    end

    # Writes the file of each built-in theme under *root* that is missing or
    # differs from the code. Answers what went wrong, or `nil`.
    def self.sync(root : Path) : String?
      BUILT_INS.each do |named|
        path = path(root, named.name) || next
        wanted = named.theme.to_named_json(named.name)
        next if File.exists?(path) && File.read(path) == wanted

        Dir.mkdir_p path.parent
        File.write path, wanted
      end
      nil
    rescue error : File::Error | IO::Error
      "The built-in theme files could not be written in #{directory root}: #{error.message}"
    end

    # *base*, or *base* with the lowest number after it that no theme file
    # and no built-in theme under *root* has.
    def self.unused_name(root : Path, base : String) : String
      wanted = base
      number = 1
      while built_in(wanted) || path(root, wanted).try { |found| File.exists? found }
        number += 1
        wanted = "#{base} #{number}"
      end
      wanted
    end

    # The directory the theme files are in under *root*.
    def self.directory(root : Path) : Path
      root / DIRECTORY
    end

    # The file name for a theme called *name*. Letters and digits are kept
    # in lower case and each run of anything else becomes one hyphen. `nil`
    # when *name* has no letter or digit.
    def self.file_name(name : String) : String?
      stem = name.downcase.gsub(/[^\p{L}\p{N}]+/, "-").strip('-')
      stem.empty? ? nil : "#{stem}.json"
    end

    # Where the file for a theme called *name* is under *root*, or `nil`
    # when *name* cannot be a file name.
    def self.path(root : Path, name : String) : Path?
      file_name(name).try { |file| directory(root) / file }
    end

    # Writes *theme* under *name* and answers the path. Raises
    # `ArgumentError` for a name with no letter or digit or the name of a
    # built-in theme, and `File::Error` when the file cannot be written.
    def self.save(root : Path, name : String, theme : Theme) : Path
      found = path root, name
      raise ArgumentError.new "a theme name needs a letter or a digit: #{name.inspect}" unless found

      owned = built_in name
      raise ArgumentError.new "#{owned.name} is one of the game's own themes" if owned

      Dir.mkdir_p found.parent
      File.write found, theme.to_named_json(name)
      found
    end

    # The theme in the file at *path*. A file with no `name` key goes by the
    # file's own name. `nil` when the file does not read.
    def self.read(path : Path) : Named?
      theme, name = Theme.parse File.read(path)
      Named.new name || path.stem, theme
    rescue File::Error | Theme::Unreadable
      nil
    end

    # Every theme to choose from: the built-in themes from the code, then
    # every other theme file under *root* that reads, ordered by name.
    def self.all(root : Path) : Array(Named)
      BUILT_INS + saved(root).reject { |named| built_in named.name }
    end

    # Every theme file under *root* that reads, ordered by name.
    def self.saved(root : Path) : Array(Named)
      found = directory root
      return [] of Named unless Dir.exists? found

      Dir.children(found)
        .select(&.ends_with?(".json"))
        .compact_map { |file| read found / file }
        .sort_by! { |named| {named.name.downcase, named.name} }
    rescue File::Error
      [] of Named
    end
  end
end
