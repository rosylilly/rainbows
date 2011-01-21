# -*- encoding: binary -*-
# :enddoc:
#
class Rainbows::Epoll::ResponsePipe
  attr_reader :io
  alias to_io io
  RBUF = Rainbows::EvCore::RBUF
  EP = Rainbows::Epoll::EP

  def initialize(io, client, body)
    @io, @client, @body = io, client, body
  end

  def epoll_run
    return close if @client.closed?
    @client.stream_pipe(self) or @client.on_deferred_write_complete
    rescue => e
      close
      @client.handle_error(e)
  end

  def close
    @io or return
    EP.delete self
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
