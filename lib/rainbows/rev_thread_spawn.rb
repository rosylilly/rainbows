# -*- encoding: binary -*-
require 'rainbows/rev'
require 'rainbows/ev_thread_core'

module Rainbows

  # A combination of the Rev and ThreadSpawn models.  This allows Ruby
  # 1.8 and 1.9 to effectively serve more than ~1024 concurrent clients
  # on systems that support kqueue or epoll while still using
  # Thread-based concurrency for application processing.  It exposes
  # Unicorn::TeeInput for a streamable "rack.input" for upload
  # processing within the app.  Threads are spawned immediately after
  # header processing is done for calling the application.  Rack
  # applications running under this mode should be thread-safe.
  # DevFdResponse should be used with this class to proxy asynchronous
  # responses.  All network I/O between the client and server are
  # handled by the main thread (even when streaming "rack.input").
  #
  # Caveats:
  #
  # * TeeInput performance under Ruby 1.8 is terrible unless you
  #   match the length argument of your env["rack.input"]#read
  #   calls so that it is greater than or equal to Rev::IO::INPUT_SIZE.
  #   Most applications depending on Rack to do multipart POST
  #   processing should be alright as the current Rev::IO::INPUT_SIZE
  #   of 16384 bytes matches the read size used by
  #   Rack::Utils::Multipart::parse_multipart.

  module RevThreadSpawn
    class Client < Rainbows::Rev::Client
      include EvThreadCore
      LOOP = ::Rev::Loop.default
      DR = Rainbows::Rev::DeferredResponse
      TEE_RESUMER = ::Rev::AsyncWatcher.new

      def pause
        @lock.synchronize { disable if enabled? }
      end

      def resume
        @lock.synchronize { enable unless enabled? }
        TEE_RESUMER.signal
      end

      def write(data)
        if Thread.current != @thread && @lock.locked?
          # we're being called inside on_writable
          super
        else
          @lock.synchronize { super }
        end
      end

      def defer_body(io, out_headers)
        @lock.synchronize { super }
      end

      def response_write(response, out)
        DR.write(self, response, out)
        (out && CONN_ALIVE == out.first) or
            @lock.synchronize {
              quit
              schedule_write
            }
      end

      def on_writable
        # don't ever want to block in the main loop with lots of clients,
        # libev is level-triggered so we'll always get another chance later
        if @lock.try_lock
          begin
            super
          ensure
            @lock.unlock
          end
        end
      end

    end

    include Rainbows::Rev::Core

    def init_worker_process(worker)
      super
      Client::TEE_RESUMER.attach(::Rev::Loop.default)
    end

  end
end
