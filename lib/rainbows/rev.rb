# -*- encoding: binary -*-
require 'rev'

# workaround revactor 0.1.4 still using the old Rev::Buffer
# ref: http://rubyforge.org/pipermail/revactor-talk/2009-October/000034.html
defined?(Rev::Buffer) or Rev::Buffer = IO::Buffer

module Rainbows

  # Implements a basic single-threaded event model with
  # {Rev}[http://rev.rubyforge.org/].  It is capable of handling
  # thousands of simultaneous client connections, but with only a
  # single-threaded app dispatch.  It is suited for slow clients and
  # fast applications (applications that do not have slow network
  # dependencies).  It does not require your Rack application to
  # be reentrant or thread-safe.
  #
  # Compatibility: Whatever \Rev itself supports, currently Ruby
  # 1.8/1.9.
  #
  # This model does not implement as streaming "rack.input" which
  # allows the Rack application to process data as it arrives.  This
  # means "rack.input" will be fully buffered in memory or to a
  # temporary file before the application is entered.
  #
  # Caveats: this model can buffer all output for slow clients in
  # memory.  This can be a problem if your application generates large
  # responses (including static files served with Rack) as it will cause
  # the memory footprint of your process to explode.  If your workers
  # seem to be eating a lot of memory from this, consider the
  # {mall}[http://bogomips.org/mall/] library which allows access to the
  # mallopt(3) function from Ruby.

  module Rev

    include Base

    class Client < ::Rev::IO
      include Unicorn
      include Rainbows::Const
      G = Rainbows::G

      def initialize(io)
        G.cur += 1
        super(io)
        @remote_addr = ::TCPSocket === io ? io.peeraddr.last : LOCALHOST
        @env = {}
        @hp = HttpParser.new
        @state = :headers # [ :body [ :trailers ] ] :app_call :close
        @buf = ""
      end

      def handle_error(e)
        @state = :close
        msg = case e
        when EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
          ERROR_500_RESPONSE
        when HttpParserError # try to tell the client they're bad
          ERROR_400_RESPONSE
        else
          G.logger.error "Read error: #{e.inspect}"
          G.logger.error e.backtrace.join("\n")
          ERROR_500_RESPONSE
        end
        write(msg)
      end

      def app_call
        @input.rewind
        @env[RACK_INPUT] = @input
        @env[REMOTE_ADDR] = @remote_addr
        response = G.app.call(@env.update(RACK_DEFAULTS))
        alive = @hp.keepalive? && G.alive
        out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if @hp.headers?
        HttpResponse.write(self, response, out)
        if alive
          @env.clear
          @hp.reset
          @state = :headers
          on_read("") # in case next request was fully-buffered
        else
          @state = :close
        end
      end

      def on_write_complete
        :close == @state and close
      end

      def on_close
        G.cur -= 1
      end

      def tmpio
        io = Util.tmpio
        def io.size
          # already sync=true at creation, so no need to flush before stat
          stat.size
        end
        io
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
            @input = len && len <= MAX_BODY ? StringIO.new("") : tmpio
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
          @hp.trailers(@env, @buf << data) and app_call
        end
        rescue Object => e
          handle_error(e)
      end
    end

    class Server < ::Rev::IO
      G = Rainbows::G

      def on_readable
        return if G.cur >= G.max
        begin
          Client.new(@_io.accept_nonblock).attach(::Rev::Loop.default)
        rescue Errno::EAGAIN, Errno::ECONNBORTED
        end
      end

    end

    # runs inside each forked worker, this sits around and waits
    # for connections and doesn't die until the parent dies (or is
    # given a INT, QUIT, or TERM signal)
    def worker_loop(worker)
      init_worker_process(worker)
      graceful_waiter = nil
      trap(:QUIT) do
        G.alive = false
        LISTENERS.map! { |s| s.close rescue nil }
        # Rev may get stuck in a loop with no events possible, spawn a new
        # thread to join on graceful exits when our client count goes to zero
        graceful_waiter = Thread.new {
          sleep(0.1) while G.cur > 0
          exit
        }
      end

      LISTENERS.map! { |s| Server.new(s).attach(::Rev::Loop.default) }
      ::Rev::Loop.default.run
      graceful_waiter.join(timeout * 2.0)
    end

  end
end
