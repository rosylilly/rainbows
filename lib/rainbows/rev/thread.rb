# -*- encoding: binary -*-
# :enddoc:
require 'thread'
require 'rainbows/rev/master'

RUBY_VERSION =~ %r{\A1\.8} && Rev::VERSION < "0.3.2" and
  warn "Rev (< 0.3.2) and Threads do not mix well under Ruby 1.8"

module Rainbows
  module Rev

    class ThreadClient < Client

      def app_call
        KATO.delete(self)
        disable
        @env[RACK_INPUT] = @input
        app_dispatch # must be implemented by subclass
      end

      # this is only called in the master thread
      def response_write(response)
        enable
        alive = @hp.keepalive? && G.alive
        out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if @hp.headers?
        rev_write_response(response, out)
        return quit unless alive && G.alive

        @env.clear
        @hp.reset
        @state = :headers
        # keepalive requests are always body-less, so @input is unchanged
        if @hp.headers(@env, @buf)
          @input = HttpRequest::NULL_IO
          app_call
        else
          KATO[self] = Time.now
        end
      end

      # fails-safe application dispatch, we absolutely cannot
      # afford to fail or raise an exception (killing the thread)
      # here because that could cause a deadlock and we'd leak FDs
      def app_response
        begin
          @env[REMOTE_ADDR] = @remote_addr
          APP.call(@env.update(RACK_DEFAULTS))
        rescue => e
          Error.app(e) # we guarantee this does not raise
          [ 500, {}, [] ]
        end
      end

    end
  end
end
