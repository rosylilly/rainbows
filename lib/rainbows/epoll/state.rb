# -*- encoding: binary -*-
# :enddoc:
# used to keep track of state for each descriptor and avoid
# unneeded syscall or ENONENT overhead
module Rainbows::Epoll::State
  EP = SleepyPenguin::Epoll.new

  def epoll_disable
    @epoll_active or return
    @epoll_active = false
    EP.del(self)
  end

  def epoll_enable(flags)
    if @epoll_active
      flags == @epoll_active or
        EP.mod(self, @epoll_active = flags)
    else
      EP.add(self, @epoll_active = flags)
    end
  end
end
