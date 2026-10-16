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
  #
  # The panel also holds the keyboard selection. It is on a section header,
  # or on one of the rows a section shows. `#up`, `#down`, `#left` and
  # `#right` move it, and `#show` draws it while the panel has the focus.
  # It stays where it was while the focus is elsewhere.
  class InfoPanel
    # What the file is called in the state directory.
    FILE = "sections.json"

    # What the file holds.
    #
    #     {"expanded": {"scores": true, "pack": false}}
    #
    # A section missing from the map is as it starts, see `CLOSED_AT_FIRST`.
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

    # The sections that start closed until the player opens one. On a 24-row
    # screen these two would push what is here, what is in sight and the
    # look readout off the first screen.
    CLOSED_AT_FIRST = {"equipment", "pack"}

    # Whether a section with *key* is open before anything is remembered.
    def self.open_at_first?(key : String) : Bool
      !CLOSED_AT_FIRST.includes? key
    end

    def initialize(@sections : Array(Widgets::Section))
      @sections.each do |section|
        section.expanded = InfoPanel.open_at_first? InfoPanel.key(section)
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

    # What a selected header is drawn through. The header keeps its text
    # colors and takes `Palette::SELECTED_HEADER` for its ground.
    HEADER_LIGHT = TermBuf::Blend.new do |_under, over, _column, _row|
      over.bg Palette::SELECTED_HEADER
    end

    # What a selected row is drawn through, the same way with
    # `Palette::SELECTED_ROW`.
    ROW_LIGHT = TermBuf::Blend.new do |_under, over, _column, _row|
      over.bg Palette::SELECTED_ROW
    end

    # The index of the section the selection is in.
    getter at : Int32 = 0

    # The index of the selected row among the section's rows, or `nil` when
    # the header is selected.
    getter row : Int32? = nil

    # The section the selection is in.
    def section : Widgets::Section
      @sections[@at]
    end

    # The selected row, or `nil` when the header is selected.
    def selected_row : Widgets::Widget?
      settle
      found = @row
      section.rows[found] if found
    end

    # The selected widget, the row or the header.
    def selected : Widgets::Widget
      selected_row || section.header
    end

    # Moves the selection down. A header goes to the next header. A row goes
    # to the next row, and the last row to the next header. Answers whether
    # it moved.
    def down : Bool
      settle
      found = @row
      if found && found + 1 < section.rows.size
        @row = found + 1
        return true
      end
      return false if @at + 1 >= @sections.size

      @at += 1
      @row = nil
      true
    end

    # Moves the selection up. A header goes to the header above it. A row
    # goes to the row above, and the first row to its own header. Answers
    # whether it moved.
    def up : Bool
      settle
      found = @row
      if found
        @row = found.zero? ? nil : found - 1
        return true
      end
      return false if @at.zero?

      @at -= 1
      true
    end

    # Takes a selected row back to its header, or closes the section when
    # its header is selected.
    def left : Nil
      settle
      if @row
        @row = nil
      elsif section.expanded?
        section.toggle
      end
    end

    # Opens a closed section, or moves from an open section's header to its
    # first row. A section with no rows keeps the selection on its header.
    def right : Nil
      settle
      return if @row
      return section.toggle unless section.expanded?

      @row = 0 unless section.rows.empty?
    end

    # Puts the selection on the header of *section*.
    def select(section : Widgets::Section) : Nil
      found = @sections.index &.same?(section)
      return unless found

      @at = found
      @row = nil
    end

    # Draws the selection when *focused*, and takes it off when not.
    def show(focused : Bool) : Nil
      settle
      wanted = focused ? selected : nil
      lit = @lit
      return if lit && wanted && lit.same?(wanted)

      lit.wash = nil if lit
      @lit = wanted
      return unless wanted

      if wanted.is_a? Widgets::Section::Header
        wanted.wash = HEADER_LIGHT
        return
      end

      # A widget with no style of its own paints no ground, so the wash
      # would reach only the cells with text in them.
      wanted.style ||= Style::DEFAULT
      wanted.wash = ROW_LIGHT
    end

    # The widget the selection is drawn on, or `nil` while it is hidden.
    getter lit : Widgets::Widget? = nil

    # Keeps the selected row inside the rows the section now shows. A
    # section that closed takes the selection back to its header.
    private def settle : Nil
      found = @row
      return unless found

      count = section.rows.size
      @row = count.zero? ? nil : Math.min(found, count - 1)
    end

    private def toggled(section : Widgets::Section) : Nil
      write
      @on_toggle.try &.call(section)
    end

    private def recall : Nil
      found = read
      @sections.each do |section|
        key = InfoPanel.key(section)
        section.expanded = found.fetch(key, InfoPanel.open_at_first?(key))
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
