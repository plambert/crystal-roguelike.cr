require "json"
require "../../crystal-roguelike"

module Roguelike::Ui
  # The sections of the info panel, and the file that remembers which of them
  # are open.
  #
  # The panel stacks the sections under the pinned vitals and scrolls them as
  # one. `Screen` holds that tree. This class holds the sections in the order
  # they are stacked, and their expansion state.
  #
  # A click on a header opens or closes its section. Each toggle writes `FILE`
  # in the state directory beside the saves. Giving the panel a path reads the
  # file back. A missing or unreadable file leaves every section open. A run
  # with no store has no path, so its sections are remembered only while it
  # runs.
  class InfoPanel
    # What the file is called in the state directory.
    FILE = "sections.json"

    # What the file holds.
    #
    #     {"expanded": {"scores": true, "pack": false}}
    #
    # A section missing from the map is open.
    struct Kept
      include JSON::Serializable

      getter expanded : Hash(String, Bool)

      def initialize(@expanded : Hash(String, Bool))
      end
    end

    # The sections, top first.
    getter sections : Array(Widgets::Section)

    # Where the expansion state is kept, or `nil` for nowhere.
    getter path : Path? = nil

    # What runs after a section opens or closes and the file is written.
    property on_toggle : Proc(Widgets::Section, Nil)? = nil

    # A section drawn the way every section of the panel is drawn.
    #
    # The header spans the panel's whole width. The body keeps one column
    # clear at each side, as the pinned vitals do.
    def self.section(title : String) : Widgets::Section
      Widgets::Section.new title, Palette::HEADER, Palette::HEADER_TITLE,
        body_padding: Layout::Padding.symmetric(horizontal: 1)
    end

    # The key a section's state is kept under.
    def self.key(section : Widgets::Section) : String
      section.title.downcase
    end

    def initialize(@sections : Array(Widgets::Section))
      @sections.each do |section|
        section.on_toggle = ->(found : Widgets::Section) { toggled found }
      end
    end

    # Keeps the expansion state at *path* and reads what is there.
    def path=(path : Path?) : Path?
      @path = path
      recall
      path
    end

    # Which sections are open, by key.
    def state : Hash(String, Bool)
      @sections.to_h { |section| {InfoPanel.key(section), section.expanded?} }
    end

    # Opens *section* unless it is open already.
    def open(section : Widgets::Section) : Nil
      section.toggle unless section.expanded?
    end

    private def toggled(section : Widgets::Section) : Nil
      write
      @on_toggle.try &.call(section)
    end

    private def recall : Nil
      found = read
      @sections.each do |section|
        section.expanded = found.fetch(InfoPanel.key(section), true)
      end
    end

    private def read : Hash(String, Bool)
      held = @path
      return {} of String => Bool unless held && File.exists?(held)

      Kept.from_json(File.read held).expanded
    rescue File::Error | IO::Error | JSON::Error
      {} of String => Bool
    end

    # The state is a convenience. A file that cannot be written is left
    # unwritten, and the game goes on.
    private def write : Nil
      held = @path
      return unless held

      Dir.mkdir_p held.parent
      File.write held, Kept.new(state).to_json
    rescue File::Error | IO::Error
    end
  end
end
