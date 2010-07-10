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
  # Ruby 1.8 users are strongly advised to use Rev >= 0.3.2 to get
  # usable performance.

  module RevThreadSpawn

    class Client < Rainbows::Rev::ThreadClient # :nodoc: all
      def app_dispatch
        Thread.new(self) { |client| MASTER << [ client, app_response ] }
      end
    end

    include Rainbows::Rev::Core

    def init_worker_process(worker) # :nodoc:
      super
      master = Rev::Master.new(Queue.new).attach(::Rev::Loop.default)
      Client.const_set(:MASTER, master)
    end

  end
end
