# -*- encoding: binary -*-
# :enddoc:
class Rainbows::Fiber::Rev::Heartbeat < Rev::TimerWatcher
  G = Rainbows::G

  # ZZ gets populated by read_expire in rainbows/fiber/io/methods
  ZZ = Rainbows::Fiber::ZZ
  def on_timer
    exit if (! G.tick && G.cur <= 0)
    now = Time.now
    fibs = []
    ZZ.delete_if { |fib, time| now >= time ? fibs << fib : ! fib.alive? }
    fibs.each { |fib| fib.resume if fib.alive? }
  end
end
