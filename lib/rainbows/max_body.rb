# -*- encoding: binary -*-
# :enddoc:
module Rainbows

# middleware used to enforce client_max_body_size for TeeInput users,
# there is no need to configure this middleware manually, it will
# automatically be configured for you based on the client_max_body_size
# setting
class MaxBody < Struct.new(:app)

  # this is meant to be included in Rainbows::TeeInput (and derived
  # classes) to limit body sizes
  module Limit
    TmpIO = Unicorn::TmpIO

    def initialize(socket, request)
      @parser = request
      @buf = request.buf
      @env = request.env
      @len = request.content_length

      max = Rainbows.max_bytes # never nil, see MaxBody.setup
      if @len && @len > max
        socket.write(Const::ERROR_413_RESPONSE)
        socket.close
        raise IOError, "Content-Length too big: #@len > #{max}", []
      end

      @socket = socket
      @buf2 = ""
      if @buf.size > 0
        parser.filter_body(@buf2, @buf) and finalize_input
        @buf2.size > max and raise IOError, "chunked request body too big", []
      end
      @tmp = @len && @len < Const::MAX_BODY ? StringIO.new("") : TmpIO.new
      if @buf2.size > 0
        @tmp.write(@buf2)
        @tmp.rewind
        max -= @buf2.size
      end
      @max_body = max
    end

    def tee(length, dst)
      rv = super
      if rv && ((@max_body -= rv.size) < 0)
        # make HttpParser#keepalive? => false to force an immediate disconnect
        # after we write
        @parser.reset
        throw :rainbows_EFBIG
      end
      rv
    end

  end

  # this is called after forking, so it won't ever affect the master
  # if it's reconfigured
  def self.setup
    Rainbows.max_bytes or return
    case G.server.use
    when :Rev, :EventMachine, :NeverBlock
      return
    end

    TeeInput.class_eval { include Limit }

    # force ourselves to the outermost middleware layer
    G.server.app = MaxBody.new(G.server.app)
  end

  # Rack response returned when there's an error
  def err(env)
    [ 413, [ %w(Content-Length 0), %w(Content-Type text/plain) ], [] ]
  end

  # our main Rack middleware endpoint
  def call(env)
    catch(:rainbows_EFBIG) { app.call(env) } || err(env)
  end

end # class
end # module
