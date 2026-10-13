# Crystal 1.22.0 resumes an isolated fiber whenever its event loop returns,
# even when no event was for that fiber. A fiber that writes and then waits to
# read on one descriptor is woken by the write readiness, retries, and queues a
# second wait while the first is still in the descriptor's waiters. The next
# wait segfaults in `Waiters#add`. The input reader runs in an isolated
# context, so the game dies on its first read.
#
# This is crystal-lang/crystal#17629. The fix is one word in
# `Isolated#wait_for`, and that method is restated here with the word changed
# for that one compiler version. Every other version compiles its own.
{% if Crystal::VERSION == "1.22.0" %}
  class Fiber::ExecutionContext::Isolated
    private def wait_for(event_loop) : Nil
      loop do
        @mutex.synchronize do
          return if check_enqueued?
          @waiting = true
        end

        done = false

        event_loop.run(blocking: true) do |fiber|
          unless fiber == @main_fiber
            raise RuntimeError.new("Concurrency is disabled in isolated contexts")
          end

          done = true
        end

        break if done
      end

      @mutex.synchronize do
        @waiting = false
        @enqueued = false
      end
    end
  end
{% end %}
