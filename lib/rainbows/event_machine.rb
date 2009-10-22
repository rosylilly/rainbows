# -*- encoding: binary -*-
require 'eventmachine'

module Rainbows

  # Implements a basic single-threaded event model with
  # {EventMachine}[http://rubyeventmachine.com/].  It is capable of
  # handling thousands of simultaneous client connections, but with only
  # a single-threaded app dispatch.  It is suited for slow clients and
  # fast applications (applications that do not have slow network
  # dependencies) or applications that use DevFdResponse for deferrable
  # response bodies.  It does not require your Rack application to be
  # thread-safe, reentrancy is only required for the DevFdResponse body
  # generator.
  #
  # Compatibility: Whatever \EventMachine and Unicorn both  support,
  # currently Ruby 1.8/1.9.
  #
  # This model does not implement as streaming "rack.input" which allows
  # the Rack application to process data as it arrives.  This means
  # "rack.input" will be fully buffered in memory or to a temporary file
  # before the application is entered.

  module EventMachine

    include Base

    class Client < EM::Connection
      include Unicorn
      include Rainbows::Const
      G = Rainbows::G

      def initialize(io)
        @_io = io
      end

      def post_init
        @remote_addr = ::TCPSocket === @_io ? @_io.peeraddr.last : LOCALHOST
        @env = {}
        @hp = HttpParser.new
        @state = :headers # [ :body [ :trailers ] ] :app_call :close
        @buf = ""
        @deferred_bodies = [] # for (fast) regular files only
      end

      # graceful exit, like SIGQUIT
      def quit
        @deferred_bodies.clear
        @state = :close
      end

      alias write send_data

      def handle_error(e)
        quit
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
        begin
          (@env[RACK_INPUT] = @input).rewind
          alive = @hp.keepalive?
          @env[REMOTE_ADDR] = @remote_addr
          response = G.app.call(@env.update(RACK_DEFAULTS))
          alive &&= G.alive
          out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if @hp.headers?

          HttpResponse.write(self, response, out)
          if alive
            @env.clear
            @hp.reset
            @state = :headers
            # keepalive requests are always body-less, so @input is unchanged
            @hp.headers(@env, @buf) and next
          else
            @state = :close
          end
          return
        end while true
      end

      def on_write_complete
        if body = @deferred_bodies.first
          return if DeferredResponse === body
          begin
            begin
              write(body.sysread(CHUNK_SIZE))
            rescue EOFError # expected at file EOF
              @deferred_bodies.shift
              body.close
              close if :close == @state && @deferred_bodies.empty?
            end
          rescue Object => e
            handle_error(e)
          end
        else
          close if :close == @state
        end
      end

      def tmpio
        io = Util.tmpio
        def io.size
          # already sync=true at creation, so no need to flush before stat
          stat.size
        end
        io
      end

      alias on_read receive_data

      # TeeInput doesn't map too well to this right now...
      def receive_data(data)
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

    module Server

      def initialize(listener, conns)
        @l = listener
        @limit = Rainbows::G.max + HttpServer::LISTENERS.size
        @em_conns = conns
      end

      def notify_readable
        return if @em_conns.size >= @limit
        begin
          io = @l.accept_nonblock
          sig = EM.attach_fd(io.fileno, false, false)
          @em_conns[sig] = Client.new(sig, io)
        rescue Errno::EAGAIN, Errno::ECONNABORTED
        end
      end
    end

    # runs inside each forked worker, this sits around and waits
    # for connections and doesn't die until the parent dies (or is
    # given a INT, QUIT, or TERM signal)
    def worker_loop(worker)
      init_worker_process(worker)
      m = 0
      EM.run {
        conns = EM.instance_variable_get(:@conns) or
          raise RuntimeError, "EM @conns instance variable not accessible!"
        EM.add_periodic_timer(1) { worker.tmp.chmod(m = 0 == m ? 1 : 0) }
        LISTENERS.each { |s| EM.attach(s, Server, s, conns) }
      }
    end

  end
end
