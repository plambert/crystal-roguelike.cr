require "./theme"

module Roguelike::Ui
  # The named theme files in `themes/` under the state directory.
  #
  # Each file holds one theme in the form of `theme.json`, with its `name`
  # key first. The file name comes from the theme's name, so saving a theme
  # under a name it already has writes over its file.
  module ThemeLibrary
    # The directory under the state root.
    DIRECTORY = "themes"

    # A theme and the name it goes by.
    record Named, name : String, theme : Theme

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
    # `ArgumentError` for a name with no letter or digit, and `File::Error`
    # when the file cannot be written.
    def self.save(root : Path, name : String, theme : Theme) : Path
      found = path root, name
      raise ArgumentError.new "a theme name needs a letter or a digit: #{name.inspect}" unless found

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
