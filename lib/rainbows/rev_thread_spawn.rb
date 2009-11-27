# -*- encoding: binary -*-
require 'rainbows/rev'

RUBY_VERSION =~ %r{\A1\.8} && ::Rev::VERSION < "0.3.2" and
  warn "Rainbows::RevThreadSpawn + Rev (< 0.3.2)" \
       " does not work well under Ruby 1.8"

module Rainbows

  # A combination of the Rev and ThreadSpawn models.  This allows Ruby
  # Thread-based concurrency for application processing.  It DOES NOT
  # expose a streamable "rack.input" for upload processing within the
  # app.  DevFdResponse should be used with this class to proxy
  # asynchronous responses.  All network I/O between the client and
  # server are handled by the main thread and outside of the core
  # application dispatch.
  #
  # WARNING: this model does not perform well under 1.8, especially
  # if your application itself performs heavy I/O

  module RevThreadSpawn

    class Master < ::Rev::AsyncWatcher

      def initialize
        super
        @queue = Queue.new
      end

      def <<(output)
        @queue << output
        signal
      end

      def on_signal
        client, response = @queue.pop
        client.response_write(response)
      end
    end

    class Client < Rainbows::Rev::Client
      DR = Rainbows::Rev::DeferredResponse
      KATO = Rainbows::Rev::KATO

      def response_write(response)
        enable
        alive = @hp.keepalive? && G.alive
        out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if @hp.headers?
        DR.write(self, response, out)
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

      def app_call
        KATO.delete(client = self)
        disable
        @env[RACK_INPUT] = @input
        @input = nil # not sure why, @input seems to get closed otherwise...
        Thread.new { MASTER << [ client, app_response ] }
      end
    end

    include Rainbows::Rev::Core

    def init_worker_process(worker)
      super
      Client.const_set(:MASTER, Master.new.attach(::Rev::Loop.default))
    end

  end
end
