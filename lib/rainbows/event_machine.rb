# -*- encoding: binary -*-
require 'eventmachine'
EM::VERSION >= '0.12.10' or abort 'eventmachine 0.12.10 is required'
require 'rainbows/ev_core'

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
  # Compatibility: Whatever \EventMachine ~> 0.12.10 and Unicorn both
  # support, currently Ruby 1.8/1.9.
  #
  # This model is compatible with users of "async.callback" in the Rack
  # environment such as
  # {async_sinatra}[http://github.com/raggi/async_sinatra].
  #
  # This model does not implement as streaming "rack.input" which allows
  # the Rack application to process data as it arrives.  This means
  # "rack.input" will be fully buffered in memory or to a temporary file
  # before the application is entered.

  module EventMachine

    include Base

    class Client < EM::Connection
      include Rainbows::EvCore
      G = Rainbows::G

      # Apps may return this Rack response: AsyncResponse = [ -1, {}, [] ]
      ASYNC_CALLBACK = 'async.callback'.freeze

      def initialize(io)
        @_io = io
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
          @env[ASYNC_CALLBACK] = method(:response_write)

          response = catch(:async) { APP.call(@env.update(RACK_DEFAULTS)) }

          # too tricky to support pipelining with :async since the
          # second (pipelined) request could be a stuck behind a
          # long-running async response
          (response.nil? || -1 == response.first) and return @state = :close

          alive = @hp.keepalive? && G.alive
          out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if @hp.headers?
          response_write(response, out, alive)

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

      def response_write(response, out = [], alive = false)
        body = response.last
        unless body.respond_to?(:to_path)
          HttpResponse.write(self, response, out)
          quit unless alive
          return
        end

        headers = Rack::Utils::HeaderHash.new(response[1])
        path = body.to_path
        io = body.to_io if body.respond_to?(:to_io)
        io ||= IO.new($1.to_i) if path =~ %r{\A/dev/fd/(\d+)\z}
        io ||= File.open(path, 'rb') # could be a named pipe

        st = io.stat
        if st.file?
          headers.delete('Transfer-Encoding')
          headers['Content-Length'] ||= st.size.to_s
          response = [ response.first, headers.to_hash, [] ]
          HttpResponse.write(self, response, out)
          stream = stream_file_data(path)
          stream.callback { quit } unless alive
        elsif st.socket? || st.pipe?
          do_chunk = !!(headers['Transfer-Encoding'] =~ %r{\Achunked\z}i)
          do_chunk = false if headers.delete('X-Rainbows-Autochunk') == 'no'
          if out.nil?
            do_chunk = false
          else
            out[0] = CONN_CLOSE
          end
          response = [ response.first, headers.to_hash, [] ]
          HttpResponse.write(self, response, out)
          if do_chunk
            EM.watch(io, ResponseChunkPipe, self).notify_readable = true
          else
            EM.enable_proxy(EM.attach(io, ResponsePipe, self), self, 16384)
          end
        else
          HttpResponse.write(self, response, out)
        end
      end

      def unbind
        @_io.close
      end
    end

    module ResponsePipe
      def initialize(client)
        @client = client
      end

      def unbind
        @io.close
        @client.quit
      end
    end

    module ResponseChunkPipe
      include ResponsePipe

      def unbind
        @client.write("0\r\n\r\n")
        super
      end

      def notify_readable
        begin
          data = begin
            @io.read_nonblock(16384)
          rescue Errno::EINTR
            retry
          rescue Errno::EAGAIN
            return
          rescue EOFError
            detach
            return
          end
          @client.send_data(sprintf("%x\r\n", data.size))
          @client.send_data(data)
          @client.send_data("\r\n")
        end while true
      end
    end

    module Server

      def close
        detach
        @io.close
      end

      def notify_readable
        return if CUR.size >= MAX
        io = Rainbows.accept(@io) or return
        sig = EM.attach_fd(io.fileno, false)
        CUR[sig] = Client.new(sig, io)
      end
    end

    # runs inside each forked worker, this sits around and waits
    # for connections and doesn't die until the parent dies (or is
    # given a INT, QUIT, or TERM signal)
    def worker_loop(worker)
      init_worker_process(worker)

      # enable them both, should be non-fatal if not supported
      EM.epoll
      EM.kqueue
      logger.info "EventMachine: epoll=#{EM.epoll?} kqueue=#{EM.kqueue?}"
      Server.const_set(:MAX, G.server.worker_connections +
                             HttpServer::LISTENERS.size)
      EvCore.setup(Client)
      EM.run {
        conns = EM.instance_variable_get(:@conns) or
          raise RuntimeError, "EM @conns instance variable not accessible!"
        Server.const_set(:CUR, conns)
        EM.add_periodic_timer(1) do
          unless G.tick
            conns.each_value { |client| Client === client and client.quit }
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
