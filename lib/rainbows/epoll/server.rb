# -*- encoding: binary -*-
# :nodoc:
module Rainbows::Epoll::Server
  IN = SleepyPenguin::Epoll::IN | SleepyPenguin::Epoll::ET
  @@nr = 0
  MAX = Rainbows.server.worker_connections
  THRESH = MAX - 1
  LISTENERS = Rainbows::HttpServer::LISTENERS
  EP = Rainbows::Epoll::EP

  def self.run
    LISTENERS.each { |sock| EP.add(sock.extend(self), IN) }
    begin
      EP.wait(nil, 1000) { |_, obj| obj.epoll_run }
      Rainbows::Epoll.rerun
      Rainbows::Epoll::Client.expire
    rescue Errno::EINTR
    rescue => e
      Rainbows::Error.listen_loop(e)
    end while Rainbows.tick || @@nr > 0
  end

  # rearms all listeners when there's a free slot
  def self.decr
    THRESH == (@@nr -= 1) and LISTENERS.each { |sock| EP.set(sock, IN) }
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
