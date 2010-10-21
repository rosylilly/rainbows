# -*- encoding: binary -*-
# :enddoc:
class Rainbows::Fiber::Rev::Sleeper < Rev::TimerWatcher

  def initialize(seconds)
    @f = Fiber.current
    super(seconds, false)
    attach(Rev::Loop.default)
    Fiber.yield
  end

  def on_timer
    @f.resume
  end
end
