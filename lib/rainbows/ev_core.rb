# -*- encoding: binary -*-

module Rainbows

  # base module for evented models like Rev and EventMachine
  module EvCore
    include Unicorn
    include Rainbows::Const
    G = Rainbows::G
    NULL_IO = Unicorn::HttpRequest::NULL_IO

    # Apps may return this Rack response: AsyncResponse = [ -1, {}, [] ]
    ASYNC_CALLBACK = "async.callback".freeze

    ASYNC_CLOSE = "async.close".freeze

    def post_init
      @remote_addr = Rainbows.addr(@_io)
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
          @input = NULL_IO
          app_call # common case
        else # nil or len > 0
          # since we don't do streaming input, we have no choice but
          # to take over 100-continue handling from the Rack application
          if @env[HTTP_EXPECT] =~ /\A100-continue\z/i
            write(EXPECT_100_RESPONSE)
            @env.delete(HTTP_EXPECT)
          end
          @input = CapInput.new(len, self)
          @hp.filter_body(@buf2 = "", @buf)
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

    class CapInput < Struct.new(:io, :client, :bytes_left)
      MAX_BODY = Unicorn::Const::MAX_BODY
      Util = Unicorn::Util

      def self.err(client, msg)
        client.write(Const::ERROR_413_RESPONSE)
        client.quit

        # zip back up the stack
        raise IOError, msg, []
      end

      def self.new(len, client)
        max = Rainbows.max_bytes
        if len
          if max && (len > max)
            err(client, "Content-Length too big: #{len} > #{max}")
          end
          len <= MAX_BODY ? StringIO.new("") : Util.tmpio
        else
          max ? super(Util.tmpio, client, max) : Util.tmpio
        end
      end

      def <<(buf)
        if (self.bytes_left -= buf.size) < 0
          io.close
          CapInput.err(client, "chunked request body too big")
        end
        io << buf
      end

      def gets; io.gets; end
      def each(&block); io.each(&block); end
      def size; io.size; end
      def rewind; io.rewind; end
      def read(*args); io.read(*args); end

    end

  end
end
