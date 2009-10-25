# -*- encoding: binary -*-
require 'eventmachine'
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
      include Rainbows::EvCore
      G = Rainbows::G

      def initialize(io)
        @_io = io
      end

      alias write send_data
      alias receive_data on_read

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
