# -*- encoding: binary -*-
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

    def worker_loop(worker)
      init_worker_process(worker)
      threads = ThreadGroup.new
      limit = worker_connections

      begin
        ret = IO.select(LISTENERS, nil, nil, 1) and
          ret.first.each do |l|
            if threads.list.size > limit # unlikely
              # Sleep if we're busy, another less busy worker process may
              # take it for us if we sleep. This is gross but other options
              # still suck because they require expensive/complicated
              # synchronization primitives for _every_ case, not just this
              # unlikely one.  Since this case is (or should be) uncommon,
              # just busy wait when we have to.
              sleep(0.1) # hope another process took it
              break # back to IO.select
            end
            c = begin
              l.accept_nonblock
            rescue Errno::EAGAIN, Errno::ECONNABORTED
            end or next
            threads.add(Thread.new { process_client(c) })
          end
      rescue Errno::EINTR
        retry
      rescue Errno::EBADF, TypeError
        break
      rescue => e
        Error.listen_loop(e)
      end while G.tick
      join_threads(threads.list)
    end

  end
end
