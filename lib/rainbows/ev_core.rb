# -*- encoding: binary -*-

module Rainbows

  # base module for evented models like Rev and EventMachine
  module EvCore
    include Unicorn
    include Rainbows::Const
    G = Rainbows::G

    # Apps may return this Rack response: AsyncResponse = [ -1, {}, [] ]
    ASYNC_CALLBACK = "async.callback".freeze

    ASYNC_CLOSE = "async.close".freeze

    def post_init
      @remote_addr = ::TCPSocket === @_io ? @_io.peeraddr.last : LOCALHOST
      @env = {}
      @hp = HttpParser.new
      @state = :headers # [ :body [ :trailers ] ] :app_call :close
      @buf = ""
    end

    # graceful exit, like SIGQUIT
    def quit
      @state = :close
    end

    def handle_error(e)
      msg = Error.response(e) and write(msg)
      ensure
        quit
    end

    # TeeInput doesn't map too well to this right now...
    def on_read(data)
      case @state
      when :headers
        @hp.headers(@env, @buf << data) or return
        @state = :body
        len = @hp.content_length
        if len == 0
          @input = HttpRequest::NULL_IO
          app_call # common case
        else # nil or len > 0
          # since we don't do streaming input, we have no choice but
          # to take over 100-continue handling from the Rack application
          if @env[HTTP_EXPECT] =~ /\A100-continue\z/i
            write(EXPECT_100_RESPONSE)
            @env.delete(HTTP_EXPECT)
          end
          @input = len && len <= MAX_BODY ? StringIO.new("") : Util.tmpio
          @hp.filter_body(@buf2 = @buf.dup, @buf)
          @input << @buf2
          on_read("")
        end
      when :body
        if @hp.body_eof?
          @state = :trailers
          on_read(data)
        elsif data.size > 0
          @hp.filter_body(@buf2, @buf << data)
          @input << @buf2
          on_read("")
        end
      when :trailers
        if @hp.trailers(@env, @buf << data)
          @input.rewind
          app_call
        end
      end
      rescue => e
        handle_error(e)
    end

  end
end
