# -*- encoding: binary -*-
class Rainbows::HttpRequest < Unicorn::HttpRequest
  attr_accessor :remote_addr

  def keepalive?
    if rv = keepalive?
      env.clear
      parser.reset
    end
    rv
  end

  def initialize(socket)
    @remote_addr = if socket.respond_to?(:kgio_addr)
      socket.kgio_addr
    elsif socket.respond_to?(:peeraddr)
      socket.peeraddr[-1]
    else
      Kgio::LOCALHOST
    end
    super()
  end

  def wait_headers_readable(socket)
    IO.select([socket], nil, nil, Rainbows::G.kato)
  end

  def tryread(socket)
    socket.kgio_read!(16384, b = buf)
    until e = parse
      wait_headers_readable(socket)
      b << socket.kgio_read!(16384)
    end
    e[Rainbows::Const::CLIENT_IO] = socket
    e[RACK_INPUT] = 0 == content_length ? NULL_IO : TeeInput.new(socket, self)
    e[REMOTE_ADDR] = @remote_addr
    e.merge!(DEFAULTS)
  end
end
