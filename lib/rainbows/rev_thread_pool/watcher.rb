# -*- encoding: binary -*-
# :enddoc:
class Rainbows::RevThreadPool::Watcher < Rev::TimerWatcher
  G = Rainbows::G

  def initialize(threads)
    @threads = threads
    super(G.server.timeout, true)
  end

  def on_timer
    @threads.each { |t| t.join(0) and G.quit! }
  end
end
