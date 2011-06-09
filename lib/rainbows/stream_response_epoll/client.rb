# -*- encoding: binary -*-
# :enddoc:
class Rainbows::StreamResponseEpoll::Client
  OUT = SleepyPenguin::Epoll::OUT
  N = Raindrops.new(1)
  EP = SleepyPenguin::Epoll.new
  timeout = Rainbows.server.timeout
  thr = Thread.new do
    begin
      EP.wait(nil, timeout) { |_,client| client.epoll_run }
    rescue Errno::EINTR
    rescue => e
      Rainbows::Error.listen_loop(e)
    end while Rainbows.alive || N[0] > 0
  end
  Rainbows.at_quit { thr.join(timeout) }

  attr_reader :to_io

  def initialize(io, unwritten)
    @closed = false
    @to_io = io.dup
    @wr_queue = [ unwritten.dup ]
    EP.set(self, OUT)
  end

  def write(str)
    @wr_queue << str.dup
  end

  def close
    @closed = true
  end

  def epoll_run
    return if @to_io.closed?
    buf = @wr_queue.shift or return on_write_complete
    case rv = @to_io.kgio_trywrite(buf)
    when nil
      buf = @wr_queue.shift or return on_write_complete
    when String # retry, socket buffer may grow
      buf = rv
    when :wait_writable
      return @wr_queue.unshift(buf)
    end while true
    rescue => err
      @to_io.close
      N.decr(0, 1)
  end

  def on_write_complete
    if @closed
      @to_io.close
      N.decr(0, 1)
    end
  end
end
