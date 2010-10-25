# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Error

  G = Rainbows::G

  # if we get any error, try to write something back to the client
  # assuming we haven't closed the socket, but don't get hung up
  # if the socket is already closed or broken.  We'll always ensure
  # the socket is closed at the end of this function
  def self.write(io, e)
    if msg = response(e)
      if io.respond_to?(:kgio_trywrite)
        io.kgio_trywrite(msg)
      else
        io.write_nonblock(msg)
      end
    end
    rescue
  end

  def self.app(e)
    G.server.logger.error "app error: #{e.inspect}"
    G.server.logger.error e.backtrace.join("\n")
    rescue
  end

  def self.listen_loop(e)
    G.alive or return
    G.server.logger.error "listen loop error: #{e.inspect}."
    G.server.logger.error e.backtrace.join("\n")
    rescue
  end

  def self.response(e)
    case e
    when EOFError, Errno::ECONNRESET, Errno::EPIPE, Errno::EINVAL,
         Errno::EBADF, Errno::ENOTCONN
      # swallow error if client shuts down one end or disconnects
    when Rainbows::Response416
      Rainbows::Const::ERROR_416_RESPONSE
    when Unicorn::HttpParserError
      Rainbows::Const::ERROR_400_RESPONSE # try to tell the client they're bad
    when IOError # HttpParserError is an IOError
    else
      app(e)
      Rainbows::Const::ERROR_500_RESPONSE
    end
  end
end
