# -*- encoding: binary -*-
# :enddoc:
class Rainbows::Fiber::Rev::Heartbeat < Rev::TimerWatcher
  G = Rainbows::G
  def on_timer
    exit if (! G.tick && G.cur <= 0)
  end
end
