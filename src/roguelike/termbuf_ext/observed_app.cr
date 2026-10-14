module TermBuf::Widgets
  # An `App` that shows each event to a watcher before the tree sees it.
  #
  # The watcher sees every event the application delivers. That includes
  # the keys and the mouse, the timers it armed, and the resizes. A caller
  # that keeps anything worked out from the screen as it was uses this to
  # learn that something may have changed.
  class ObservedApp < App
    # What sees each event first. `nil` watches nothing.
    property on_deliver : Proc(Event, Nil)? = nil

    protected def deliver(event : Event) : Nil
      @on_deliver.try &.call(event)
      super
    end
  end
end
