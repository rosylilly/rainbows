# -*- encoding: binary -*-
# :enddoc:

module Rainbows::XEpoll::Client
  N = Raindrops.new(1)
  include Rainbows::Epoll::Client
  ACCEPTORS = Rainbows::HttpServer::LISTENERS.dup
  extend Rainbows::WorkerYield

  def self.included(klass)
    max = Rainbows.server.worker_connections
    ACCEPTORS.map! do |sock|
      Thread.new do
        begin
          if io = sock.kgio_accept(klass)
            N.incr(0, 1)
            io.epoll_once
          end
          worker_yield while N[0] >= max
        rescue => e
          Rainbows::Error.listen_loop(e)
        end while Rainbows.alive
      end
    end
  end

  def self.loop
    begin
      EP.wait(nil, 1000) { |_, obj| obj.epoll_run }
      while obj = ReRun.shift
        obj.epoll_run
      end
      Rainbows::Epoll::Client.expire
    rescue Errno::EINTR
    rescue => e
      Rainbows::Error.listen_loop(e)
    end while Rainbows.tick || N[0] > 0
    Rainbows::JoinThreads.acceptors(ACCEPTORS)
  end

  # only call this once
  def epoll_once
    @wr_queue = [] # may contain String, ResponsePipe, and StreamFile objects
    post_init
    EP.set(self, IN) # wake up the main thread
    rescue => e
      Rainbows::Error.write(self, e)
  end

  def on_close
    KATO.delete(self)
    N.decr(0, 1)
  end
end
