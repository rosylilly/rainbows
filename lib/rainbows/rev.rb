# -*- encoding: binary -*-
require 'rev'

module Rainbows

  # Implements a basic single-threaded event model with
  # {Rev}[http://rev.rubyforge.org/].  It is capable of handling
  # thousands of simultaneous client connections, but with only a
  # single-threaded app dispatch.  It is suited for slow clients and
  # fast applications (applications that do not have slow network
  # dependencies) or applications that use DevFdResponse for deferrable
  # response bodies.  It does not require your Rack application to be
  # thread-safe, reentrancy is only required for the DevFdResponse body
  # generator.
  #
  # Compatibility: Whatever \Rev itself supports, currently Ruby
  # 1.8/1.9.
  #
  # This model does not implement as streaming "rack.input" which
  # allows the Rack application to process data as it arrives.  This
  # means "rack.input" will be fully buffered in memory or to a
  # temporary file before the application is entered.

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
        @deferred_bodies = [] # for (fast) regular files only
      end

      # graceful exit, like SIGQUIT
      def quit
        @deferred_bodies.clear
        @state = :close
      end

      # queued, optional response bodies, it should only be unpollable "fast"
      # devices where read(2) is uninterruptable.  Unfortunately, NFS and ilk
      # are also part of this.  We'll also stick DeferredResponse bodies in
      # here to prevent connections from being closed on us.
      def defer_body(io)
        @deferred_bodies << io
        on_write_complete unless @hp.headers? # triggers a write
      end

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

          DeferredResponse.write(self, response, out)
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
        rescue Errno::EAGAIN, Errno::ECONNABORTED
        end
      end

    end

    class DeferredResponse < ::Rev::IO
      include Unicorn
      include Rainbows::Const
      G = Rainbows::G

      def self.defer!(client, response, out)
        body = response.last
        headers = Rack::Utils::HeaderHash.new(response[1])

        # to_io is not part of the Rack spec, but make an exception
        # here since we can't get here without checking to_path first
        io = body.to_io if body.respond_to?(:to_io)
        io ||= ::IO.new($1.to_i) if body.to_path =~ %r{\A/dev/fd/(\d+)\z}
        io ||= File.open(File.expand_path(body.to_path), 'rb')
        st = io.stat

        if st.socket? || st.pipe?
          do_chunk = !!(headers['Transfer-Encoding'] =~ %r{\Achunked\z}i)
          do_chunk = false if headers.delete('X-Rainbows-Autochunk') == 'no'
          # too tricky to support keepalive/pipelining when a response can
          # take an indeterminate amount of time here.
          if out.nil?
            do_chunk = false
          else
            out[0] = CONN_CLOSE
          end

          io = new(io, client, do_chunk, body).attach(::Rev::Loop.default)
        elsif st.file?
          headers.delete('Transfer-Encoding')
          headers['Content-Length'] ||= st.size.to_s
        else # char/block device, directory, whatever... nobody cares
          return response
        end
        client.defer_body(io)
        [ response.first, headers.to_hash, [] ]
      end

      def self.write(client, response, out)
        response.last.respond_to?(:to_path) and
          response = defer!(client, response, out)
        HttpResponse.write(client, response, out)
      end

      def initialize(io, client, do_chunk, body)
        super(io)
        @client, @do_chunk, @body = client, do_chunk, body
      end

      def on_read(data)
        @do_chunk and @client.write(sprintf("%x\r\n", data.size))
        @client.write(data)
        @do_chunk and @client.write("\r\n")
      end

      def on_close
        @do_chunk and @client.write("0\r\n\r\n")
        @client.quit
        @body.respond_to?(:close) and @body.close
      end
    end

    # This timer handles the fchmod heartbeat to prevent our master
    # from killing us.
    class Heartbeat < ::Rev::TimerWatcher
      G = Rainbows::G

      def initialize(tmp)
        @m, @tmp = 0, tmp
        super(1, true)
      end

      def on_timer
        @tmp.chmod(@m = 0 == @m ? 1 : 0)
        exit if (! G.alive && G.cur <= 0)
      end
    end

    # runs inside each forked worker, this sits around and waits
    # for connections and doesn't die until the parent dies (or is
    # given a INT, QUIT, or TERM signal)
    def worker_loop(worker)
      init_worker_process(worker)
      rloop = ::Rev::Loop.default
      Heartbeat.new(worker.tmp).attach(rloop)
      LISTENERS.map! { |s| Server.new(s).attach(rloop) }
      rloop.run
    end

  end
end
