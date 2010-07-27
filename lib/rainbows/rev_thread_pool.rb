# -*- encoding: binary -*-
require 'rainbows/rev/thread'

module Rainbows

  # A combination of the Rev and ThreadPool models.  This allows Ruby
  # Thread-based concurrency for application processing.  It DOES NOT
  # expose a streamable "rack.input" for upload processing within the
  # app.  DevFdResponse should be used with this class to proxy
  # asynchronous responses.  All network I/O between the client and
  # server are handled by the main thread and outside of the core
  # application dispatch.
  #
  # Unlike ThreadPool, Rev makes this model highly suitable for
  # slow clients and applications with medium-to-slow response times
  # (I/O bound), but less suitable for sleepy applications.
  #
  # This concurrency model is designed for Ruby 1.9, and Ruby 1.8
  # users are NOT advised to use this due to high CPU usage.

  module RevThreadPool

    # :stopdoc:
    DEFAULTS = {
      :pool_size => 20, # same default size as ThreadPool (w/o Rev)
    }
    #:startdoc:

    def self.setup # :nodoc:
      DEFAULTS.each { |k,v| O[k] ||= v }
      Integer === O[:pool_size] && O[:pool_size] > 0 or
        raise ArgumentError, "pool_size must a be an Integer > 0"
    end

    class PoolWatcher < ::Rev::TimerWatcher # :nodoc: all
      def initialize(threads)
        @threads = threads
        super(G.server.timeout, true)
      end

      def on_timer
        @threads.each { |t| t.join(0) and G.quit! }
      end
    end

    class Client < Rainbows::Rev::ThreadClient # :nodoc:
      def app_dispatch
        QUEUE << self
      end
    end

    include Rainbows::Rev::Core

    def init_worker_threads(master, queue) # :nodoc:
      O[:pool_size].times.map do
        Thread.new do
          begin
            client = queue.pop
            master << [ client, client.app_response ]
          rescue => e
            Error.listen_loop(e)
          end while true
        end
      end
    end

    def init_worker_process(worker) # :nodoc:
      super
      master = Rev::Master.new(Queue.new).attach(::Rev::Loop.default)
      queue = Client.const_set(:QUEUE, Queue.new)
      threads = init_worker_threads(master, queue)
      PoolWatcher.new(threads).attach(::Rev::Loop.default)
      logger.info "RevThreadPool pool_size=#{O[:pool_size]}"
    end
  end
end
