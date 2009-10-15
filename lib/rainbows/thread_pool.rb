# -*- encoding: binary -*-

module Rainbows

  # Implements a worker thread pool model.  This is suited for platforms
  # where the cost of dynamically spawning a new thread for every new
  # client connection is too high.
  #
  # Applications using this model are required to be thread-safe.
  # Threads are never spawned dynamically under this model.  If you're
  # connecting to external services and need to perform DNS lookups,
  # consider using the "resolv-replace" library which replaces parts of
  # the core Socket package with concurrent DNS lookup capabilities.
  #
  # This model is less suited for many slow clients than the others and
  # thus a lower +worker_connections+ setting is recommended.
  module ThreadPool

    include Base

    def worker_loop(worker)
      init_worker_process(worker)
      RACK_DEFAULTS["rack.multithread"] = true
      pool = (1..worker_connections).map { new_worker_thread }
      m = 0

      while LISTENERS.first && master_pid == Process.ppid
        pool.each do |thr|
          worker.tmp.chmod(m = 0 == m ? 1 : 0)
          # if any worker dies, something is serious wrong, bail
          thr.join(timeout) and break
        end
      end
      join_threads(pool, worker)
    end

    def new_worker_thread
      Thread.new {
        begin
          begin
            ret = IO.select(LISTENERS, nil, nil, timeout) or next
            ret.first.each do |sock|
              begin
                process_client(sock.accept_nonblock)
              rescue Errno::EAGAIN, Errno::ECONNABORTED
              end
            end
          rescue Errno::EINTR
            next
          rescue Errno::EBADF, TypeError
            return
          end
        rescue Object => e
          listen_loop_error(e) if LISTENERS.first
        end while ! Thread.current[:quit] && LISTENERS.first
      }
    end

  end
end
