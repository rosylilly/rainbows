# -*- encoding: binary -*-
# :stopdoc:
# FIXME: fails many tests, experimental
require 'rainbows/event_machine'

module Rainbows

  # This is currently highly experimental
  module EventMachineDefer
    include Rainbows::EventMachine

    class Client < Rainbows::EventMachine::Client
      undef_method :app_call

      def defer_op
        @env[RACK_INPUT] = @input
        @env[REMOTE_ADDR] = @remote_addr
        @env[ASYNC_CALLBACK] = method(:response_write)
        catch(:async) { APP.call(@env.update(RACK_DEFAULTS)) }
        rescue => e
          handle_error(e)
          nil
      end

      def defer_callback(response)
        # too tricky to support pipelining with :async since the
        # second (pipelined) request could be a stuck behind a
        # long-running async response
        (response.nil? || -1 == response.first) and return @state = :close

        resume

        alive = @hp.keepalive? && G.alive
        out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if @hp.headers?
        response_write(response, out, alive)
        if alive
          @env.clear
          @hp.reset
          @state = :headers
          if @hp.headers(@env, @buf)
            EM.next_tick(method(:app_call))
          else
            set_comm_inactivity_timeout(G.kato)
          end
        else
          quit
        end
      end

      def app_call
        pause
        set_comm_inactivity_timeout(0)
        # defer_callback(defer_op)
        EM.defer(method(:defer_op), method(:defer_callback))
      end
    end

  end
end
