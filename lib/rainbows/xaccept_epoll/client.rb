# -*- encoding: binary -*-
# :enddoc:

module Rainbows::XAcceptEpoll::Client
  include Rainbows::Epoll::Client
  MAX = Rainbows.server.worker_connections
  THRESH = MAX - 1
  EP = Rainbows::Epoll::EP
  N = Raindrops.new(1)
  @timeout = Rainbows.server.timeout / 2.0
  THREADS = Rainbows::HttpServer::LISTENERS.map do |sock|
    Thread.new(sock) do |sock|
      sleep
      begin
        if io = sock.kgio_accept
          N.incr(0, 1)
          io.epoll_once
        end
        sleep while N[0] >= MAX
      rescue => e
        Rainbows::Error.listen_loop(e)
      end while Rainbows.alive
    end
  end

  def self.run
    THREADS.each { |t| t.run }
    begin
      EP.wait(nil, @timeout) { |flags, obj| obj.epoll_run }
      Rainbows::Epoll::Client.expire
    rescue => e
      Rainbows::Error.listen_loop(e)
    end while Rainbows.tick

    THREADS.delete_if do |thr|
      Rainbows.tick
      begin
        thr.run
        thr.join(0.01)
      rescue
        true
      end
    end until THREADS.empty?
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
    N.decr(0, 1) == THRESH and THREADS.each { |t| t.run }
  end
end
