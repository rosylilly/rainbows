# -*- encoding: binary -*-
require 'rainbows/rev/thread'

module Rainbows

  # A combination of the Rev and ThreadSpawn models.  This allows Ruby
  # Thread-based concurrency for application processing.  It DOES NOT
  # expose a streamable "rack.input" for upload processing within the
  # app.  DevFdResponse should be used with this class to proxy
  # asynchronous responses.  All network I/O between the client and
  # server are handled by the main thread and outside of the core
  # application dispatch.
  #
  # Unlike ThreadSpawn, Rev makes this model highly suitable for
  # slow clients and applications with medium-to-slow response times
  # (I/O bound), but less suitable for sleepy applications.
  #
  # WARNING: this model does not currently perform well under 1.8 with
  # Rev 0.3.1.  Rev 0.3.2 should include significant performance
  # improvements under Ruby 1.8.

  module RevThreadSpawn

    class Client < Rainbows::Rev::ThreadClient
      def app_dispatch
        Thread.new(self) { |client| MASTER << [ client, app_response ] }
      end
    end

    include Rainbows::Rev::Core

    def init_worker_process(worker)
      super
      master = Rev::Master.new(Queue.new).attach(::Rev::Loop.default)
      Client.const_set(:MASTER, master)
    end

  end
end
