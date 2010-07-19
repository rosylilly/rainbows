# -*- encoding: binary -*-
require 'eventmachine'
EM::VERSION >= '0.12.10' or abort 'eventmachine 0.12.10 is required'
require 'rainbows/ev_core'

module Rainbows

  # Implements a basic single-threaded event model with
  # {EventMachine}[http://rubyeventmachine.com/].  It is capable of
  # handling thousands of simultaneous client connections, but with only
  # a single-threaded app dispatch.  It is suited for slow clients,
  # and can work with slow applications via asynchronous libraries such as
  # {async_sinatra}[http://github.com/raggi/async_sinatra],
  # {Cramp}[http://m.onkey.org/2010/1/7/introducing-cramp],
  # and {rack-fiber_pool}[http://github.com/mperham/rack-fiber_pool].
  #
  # It does not require your Rack application to be thread-safe,
  # reentrancy is only required for the DevFdResponse body
  # generator.
  #
  # Compatibility: Whatever \EventMachine ~> 0.12.10 and Unicorn both
  # support, currently Ruby 1.8/1.9.
  #
  # This model is compatible with users of "async.callback" in the Rack
  # environment such as
  # {async_sinatra}[http://github.com/raggi/async_sinatra].
  #
  # For a complete asynchronous framework,
  # {Cramp}[http://m.onkey.org/2010/1/7/introducing-cramp] is fully
  # supported when using this concurrency model.
  #
  # This model is fully-compatible with
  # {rack-fiber_pool}[http://github.com/mperham/rack-fiber_pool]
  # which allows each request to run inside its own \Fiber after
  # all request processing is complete.
  #
  # Merb (and other frameworks/apps) supporting +deferred?+ execution as
  # documented at http://brainspl.at/articles/2008/04/18/deferred-requests-with-merb-ebb-and-thin
  # will also get the ability to conditionally defer request processing
  # to a separate thread.
  #
  # This model does not implement as streaming "rack.input" which allows
  # the Rack application to process data as it arrives.  This means
  # "rack.input" will be fully buffered in memory or to a temporary file
  # before the application is entered.

  module EventMachine

    include Base

    class Client < EM::Connection # :nodoc: all
      include Rainbows::EvCore
      G = Rainbows::G

      def initialize(io)
        @_io = io
        @body = nil
      end

      alias write send_data
      alias receive_data on_read

      def quit
        super
        close_connection_after_writing
      end

      def app_call
        set_comm_inactivity_timeout 0
        begin
          @env[RACK_INPUT] = @input
          @env[REMOTE_ADDR] = @remote_addr
          @env[ASYNC_CALLBACK] = method(:em_write_response)

          # we're not sure if anybody uses this, but Thin sets it, too
          @env[ASYNC_CLOSE] = EM::DefaultDeferrable.new

          response = catch(:async) { APP.call(@env.update(RACK_DEFAULTS)) }

          # too tricky to support pipelining with :async since the
          # second (pipelined) request could be a stuck behind a
          # long-running async response
          (response.nil? || -1 == response[0]) and return @state = :close

          em_write_response(response, alive = @hp.keepalive? && G.alive)
          if alive
            @env.clear
            @hp.reset
            @state = :headers
            # keepalive requests are always body-less, so @input is unchanged
            @hp.headers(@env, @buf) and next
            set_comm_inactivity_timeout G.kato
          end
          return
        end while true
      end

      # used for streaming sockets and pipes
      def stream_response(status, headers, io)
        do_chunk = stream_response_headers(status, headers) if headers
        mod = do_chunk ? ResponseChunkPipe : ResponsePipe
        EM.watch(io, mod, self).notify_readable = true
      end

      def em_write_response(response, alive = false)
        status, headers, body = response
        headers = @hp.headers? ? HH.new(headers) : nil if headers
        @body = body

        if body.respond_to?(:errback) && body.respond_to?(:callback)
          body.callback { quit }
          body.errback { quit }
          # async response, this could be a trickle as is in comet-style apps
          if headers
            headers[CONNECTION] = CLOSE
            write(response_header(status, headers))
          end
          return write_body_each(self, body)
        elsif body.respond_to?(:to_path)
          io = body_to_io(body)
          st = io.stat

          if st.file?
            if headers
              headers[CONNECTION] = alive ? KEEP_ALIVE : CLOSE
              write(response_header(status, headers))
            end
            stream = stream_file_data(body.to_path)
            stream.callback { quit } unless alive
            return
          elsif st.socket? || st.pipe?
            return stream_response(status, headers, io)
          end
          # char or block device... WTF? fall through to body.each
        end

        if headers
          headers[CONNECTION] = alive ? KEEP_ALIVE : CLOSE
          write(response_header(status, headers))
        end
        write_body_each(self, body)
        quit unless alive
      end

      def unbind
        async_close = @env[ASYNC_CLOSE] and async_close.succeed
        @body.respond_to?(:fail) and @body.fail
        @_io.close
      end
    end

    module ResponsePipe # :nodoc: all
      # garbage avoidance, EM always uses this in a single thread,
      # so a single buffer for all clients will work safely
      BUF = ''

      def initialize(client)
        @client = client
      end

      def notify_readable
        begin
          @client.write(@io.read_nonblock(16384, BUF))
        rescue Errno::EINTR
          retry
        rescue Errno::EAGAIN
          return
        rescue EOFError
          detach
          return
        end while true
      end

      def unbind
        @io.close
        @client.quit
      end
    end

    module ResponseChunkPipe # :nodoc: all
      include ResponsePipe

      def unbind
        @client.write("0\r\n\r\n")
        super
      end

      def notify_readable
        begin
          data = @io.read_nonblock(16384, BUF)
          @client.write(sprintf("%x\r\n", data.size))
          @client.write(data)
          @client.write("\r\n")
        rescue Errno::EINTR
          retry
        rescue Errno::EAGAIN
          return
        rescue EOFError
          detach
          return
        end while true
      end
    end

    module Server # :nodoc: all

      def close
        detach
        @io.close
      end

      def notify_readable
        return if CUR.size >= MAX
        io = Rainbows.accept(@io) or return
        sig = EM.attach_fd(io.fileno, false)
        CUR[sig] = CL.new(sig, io)
      end
    end

    # Middleware that will run the app dispatch in a separate thread.
    # This middleware is automatically loaded by Rainbows! when using
    # EventMachine and if the app responds to the +deferred?+ method.
    class TryDefer < Struct.new(:app) # :nodoc: all

      def initialize(app)
        # the entire app becomes multithreaded, even the root (non-deferred)
        # thread since any thread can share processes with others
        Const::RACK_DEFAULTS['rack.multithread'] = true
        super
      end

      def call(env)
        if app.deferred?(env)
          EM.defer(proc { catch(:async) { app.call(env) } },
                   env[EvCore::ASYNC_CALLBACK])
          # all of the async/deferred stuff breaks Rack::Lint :<
          nil
        else
          app.call(env)
        end
      end
    end

    def init_worker_process(worker) # :nodoc:
      Rainbows::Response.setup(Rainbows::EventMachine::Client)
      super
    end

    # runs inside each forked worker, this sits around and waits
    # for connections and doesn't die until the parent dies (or is
    # given a INT, QUIT, or TERM signal)
    def worker_loop(worker) # :nodoc:
      init_worker_process(worker)
      G.server.app.respond_to?(:deferred?) and
        G.server.app = TryDefer[G.server.app]

      # enable them both, should be non-fatal if not supported
      EM.epoll
      EM.kqueue
      logger.info "#@use: epoll=#{EM.epoll?} kqueue=#{EM.kqueue?}"
      client_class = Rainbows.const_get(@use).const_get(:Client)
      Server.const_set(:MAX, worker_connections + LISTENERS.size)
      Server.const_set(:CL, client_class)
      client_class.const_set(:APP, G.server.app)
      EM.run {
        conns = EM.instance_variable_get(:@conns) or
          raise RuntimeError, "EM @conns instance variable not accessible!"
        Server.const_set(:CUR, conns)
        EM.add_periodic_timer(1) do
          unless G.tick
            conns.each_value { |c| client_class === c and c.quit }
            EM.stop if conns.empty? && EM.reactor_running?
          end
        end
        LISTENERS.map! do |s|
          EM.watch(s, Server) { |c| c.notify_readable = true }
        end
      }
    end

  end
end
