# -*- encoding: binary -*-
module Rainbows

  # Spawns a new thread for every client connection we accept().  This
  # model is recommended for platforms where spawning threads is
  # inexpensive.
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
      alive = worker.tmp
      m = 0
      limit = worker_connections

      begin
        ret = begin
          alive.chmod(m = 0 == m ? 1 : 0)
          IO.select(LISTENERS, nil, nil, timeout) or next
        rescue Errno::EINTR
          retry
        rescue Errno::EBADF, TypeError
          break
        end
        alive.chmod(m = 0 == m ? 1 : 0)

        ret.first.each do |l|
          # Sleep if we're busy, another less busy worker process may
          # take it for us if we sleep. This is gross but other options
          # still suck because they require expensive/complicated
          # synchronization primitives for _every_ case, not just this
          # unlikely one.  Since this case is (or should be) uncommon,
          # just busy wait when we have to.
          while threads.list.size > limit # unlikely
            sleep(0.1) # hope another process took it
            break # back to IO.select
          end
          begin
            threads.add(Thread.new(l.accept_nonblock) {|c| process_client(c) })
          rescue Errno::EAGAIN, Errno::ECONNABORTED
          end
        end
      rescue Object => e
        listen_loop_error(e) if LISTENERS.first
      end while LISTENERS.first && master_pid == Process.ppid
      join_threads(threads.list)
    end

  end
end
