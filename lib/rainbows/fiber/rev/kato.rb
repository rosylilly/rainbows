# -*- encoding: binary -*-
# :enddoc:
# keep-alive timeout class
class Rainbows::Fiber::Rev::Kato < Rev::TimerWatcher
  def initialize
    @watch = []
    super(1, true)
  end

  def <<(fiber)
    @watch << fiber
    enable unless enabled?
  end

  def on_timer
    @watch.uniq!
    while f = @watch.shift
      f.resume if f.alive?
    end
    disable
  end
end
