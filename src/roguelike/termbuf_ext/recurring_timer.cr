require "termbuf-widgets"

module TermBuf::Widgets
  # Owns one pending timer in a recurring chain.
  #
  # A callback releases its timer before it runs, so it can arm the next one.
  # Cancellation invalidates callbacks that are already on their way.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`.
  class RecurringTimer
    private getter app : App? = nil
    private getter nonce : UInt64? = nil
    private getter generation : UInt64 = 0

    # Arms one callback, or answers whether the same app already has one.
    # With no app or clock, the caller can continue synchronously.
    def after(app : App?, span : Time::Span, &callback : -> Nil) : Bool
      if @nonce
        current = @app
        return true if current && app && current.same?(app)

        cancel
      end

      return false unless app

      @generation += 1
      generation = @generation
      nonce : UInt64? = nil
      armed = app.after(span) do
        if generation == @generation && @nonce == nonce
          @nonce = nil
          @app = nil
          @generation += 1
          callback.call
        end
        nil
      end
      return false unless armed

      nonce = armed
      @app = app
      @nonce = armed
      true
    end

    # Whether a callback is waiting.
    def pending? : Bool
      !@nonce.nil?
    end

    # Cancels the callback and invalidates it if it has already been dequeued.
    def cancel : Nil
      @generation += 1
      nonce = @nonce
      app = @app
      @nonce = nil
      @app = nil
      app.try &.cancel(nonce) if nonce
    end
  end
end
