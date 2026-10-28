require "termbuf-widgets"

module TermBuf::Widgets
  # The keys and row presentation a navigation widget uses.
  #
  # Bindings are independent keys rather than sequences. This lets a widget
  # install them in its own scope without taking ownership of application keys.
  record Navigation,
    previous_row : Array(Key) = Key.parse("Up"),
    next_row : Array(Key) = Key.parse("Down"),
    previous_tab : Array(Key) = Key.parse("Left"),
    next_tab : Array(Key) = Key.parse("Right"),
    activate : Array(Key) = Key.parse("Enter"),
    cancel : Array(Key) = Key.parse("Escape"),
    page_up : Array(Key) = Key.parse("PageUp"),
    page_down : Array(Key) = Key.parse("PageDown"),
    first_row : Array(Key) = Key.parse("Home"),
    last_row : Array(Key) = Key.parse("End"),
    row_shortcuts : Bool = true,
    display_shortcuts : Bool = true do
    # Letterless row and tab navigation with function-key activation.
    def self.selectable : Navigation
      new previous_row: Key.parse("Up w"),
        next_row: Key.parse("Down s"),
        previous_tab: Key.parse("Left a"),
        next_tab: Key.parse("Right d"),
        activate: Key.parse("Enter f"),
        cancel: Key.parse("Escape"),
        row_shortcuts: false,
        display_shortcuts: false
    end
  end
end
