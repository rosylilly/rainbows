# -*- encoding: binary -*-
require 'thread'
module Rainbows

  # Spawns a new thread for every client connection we accept().  This
  # model is recommended for platforms like Ruby 1.8 where spawning new
  # threads is inexpensive.
  #
  # This model should provide a high level of compatibility with all
  # Ruby implementations, and most libraries and applications.
  # Applications running under this model should be thread-safe
  # but not necessarily reentrant.
  #
  # If you're connecting to external services and need to perform DNS
  # lookups, consider using the "resolv-replace" library which replaces
  # parts of the core Socket package with concurrent DNS lookup
  # capabilities

  module ThreadSpawn

    include Base

    def accept_loop(klass)
      lock = Mutex.new
      limit = worker_connections
      LISTENERS.each do |l|
        klass.new(l) do |l|
          begin
            if lock.synchronize { G.cur >= limit }
              # Sleep if we're busy, another less busy worker process may
              # take it for us if we sleep. This is gross but other options
              # still suck because they require expensive/complicated
              # synchronization primitives for _every_ case, not just this
              # unlikely one.  Since this case is (or should be) uncommon,
              # just busy wait when we have to.
              sleep(0.01)
            elsif c = Rainbows.sync_accept(l)
              klass.new(c) do |c|
                begin
                  lock.synchronize { G.cur += 1 }
                  process_client(c)
                ensure
                  lock.synchronize { G.cur -= 1 }
                end
              end
            end
          rescue => e
            Error.listen_loop(e)
          end while G.alive
        end
      end
      sleep 1 while G.tick || lock.synchronize { G.cur > 0 }
    end

    def worker_loop(worker)
      init_worker_process(worker)
      accept_loop(Thread)
    end
  end
end
