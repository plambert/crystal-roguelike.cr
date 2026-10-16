module TermBuf::Widgets
  # An `App` that shows each event to a watcher before the tree sees it.
  #
  # The watcher sees every event the application delivers. That includes
  # the keys and the mouse, the timers it armed, and the resizes. A caller
  # that keeps anything worked out from the screen as it was uses this to
  # learn that something may have changed.
  #
  # A mouse report outside the tree's screen rectangle is not delivered. An
  # application drawn in part of the terminal does not answer the pointer in
  # the rest of it. `#on_outside` sees such a report instead. A button
  # pressed inside holds the mouse until it is let go, so a drag that starts
  # inside goes on following the pointer past the edge.
  class ObservedApp < App
    # What sees each event first. `nil` watches nothing.
    property on_deliver : Proc(Event, Nil)? = nil

    # What sees a mouse report that lands outside the screen rectangle.
    # `nil` drops it unseen.
    property on_outside : Proc(Event, Nil)? = nil

    # Whether a button went down inside and has not come up yet.
    @held = false

    protected def deliver(event : Event) : Nil
      if event.is_a?(TermBuf::Events::Mouse) && !admitted?(event)
        @on_outside.try &.call(event)
        return
      end

      @on_deliver.try &.call(event)
      super
    end

    # Whether *report* reaches the tree.
    private def admitted?(report : TermBuf::Events::Mouse) : Bool
      inside = tree.screen.contains? report.x, report.y

      case report.action
      in .press?
        @held = inside unless report.button.wheel?
        inside
      in .release?
        held = @held
        @held = false
        inside || held
      in .motion?
        inside || @held
      end
    end
  end
end
