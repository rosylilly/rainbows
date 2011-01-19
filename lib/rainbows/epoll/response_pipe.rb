# -*- encoding: binary -*-
# :enddoc:
#
class Rainbows::Epoll::ResponsePipe
  include Rainbows::Epoll::State
  attr_reader :io
  alias to_io io
  IN = SleepyPenguin::Epoll::IN | SleepyPenguin::Epoll::ET
  RBUF = Rainbows::EvCore::RBUF

  def initialize(io, client, body)
    @io, @client, @body = io, client, body
    @epoll_active = false
  end

  def epoll_run
    return close if @client.closed?
    @client.stream_pipe(self) or @client.on_deferred_write_complete
    rescue => e
      close
      @client.handle_error(e)
  end

  def close
    epoll_disable
    @body.respond_to?(:close) and @body.close
    @io = @body = nil
  end

  def tryread
    io = @io
    io.respond_to?(:kgio_tryread) and return io.kgio_tryread(16384, RBUF)
    io.read_nonblock(16384, RBUF)
    rescue Errno::EAGAIN
      :wait_readable
    rescue EOFError
  end
end
