# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Epoll::Server
  @@nr = 0
  IN = SleepyPenguin::Epoll::IN | SleepyPenguin::Epoll::ET
  MAX = Rainbows.server.worker_connections
  THRESH = MAX - 1
  LISTENERS = Rainbows::HttpServer::LISTENERS
  EP = Rainbows::EP

  def self.nr
    @@nr
  end

  # rearms all listeners when there's a free slot
  def self.decr
    THRESH == (@@nr -= 1) and LISTENERS.each { |sock| EP.set(sock, IN) }
  end

  def self.extended(sock)
    EP.set(sock, IN)
  end

  def epoll_run
    return EP.delete(self) if @@nr >= MAX
    while io = kgio_tryaccept
      @@nr += 1
      # there's a chance the client never even sees epoll for simple apps
      io.epoll_once
      return EP.delete(self) if @@nr >= MAX
    end
  end
end
