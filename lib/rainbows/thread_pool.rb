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
      threads = ThreadGroup.new
      alive = worker.tmp
      nr = 0

      # closing anything we IO.select on will raise EBADF
      trap(:USR1) { reopen_worker_logs(worker.nr) rescue nil }
      trap(:QUIT) { alive = false; LISTENERS.map! { |s| s.close rescue nil } }
      [:TERM, :INT].each { |sig| trap(sig) { exit(0) } } # instant shutdown
      logger.info "worker=#{worker.nr} ready with ThreadPool"

      while alive && master_pid == Process.ppid
        maintain_thread_count(threads)
        threads.list.each do |thr|
          alive.chmod(nr += 1)
          thr.join(timeout / 2.0) and break
        end
      end
      join_worker_threads(threads)
    end

    def join_worker_threads(threads)
      logger.info "Joining worker threads..."
      t0 = Time.now
      timeleft = timeout
      threads.list.each { |thr|
        thr.join(timeleft)
        timeleft -= (Time.now - t0)
      }
      logger.info "Done joining worker threads."
    end

    def maintain_thread_count(threads)
      threads.list.each do |thr|
        next if (Time.now - (thr[:t] || next)) < timeout
        thr.kill
        logger.error "killed #{thr.inspect} for being too old"
      end

      while threads.list.size < worker_connections
        threads.add(new_worker_thread)
      end
    end

    def new_worker_thread
      Thread.new {
        alive = true
        thr = Thread.current
        begin
          ret = begin
            thr[:t] = Time.now
            IO.select(LISTENERS, nil, nil, timeout/2.0) or next
          rescue Errno::EINTR
            retry
          rescue Errno::EBADF
            return
          end
          ret.first.each do |sock|
            begin
              process_client(sock.accept_nonblock)
            rescue Errno::EAGAIN, Errno::ECONNABORTED
            end
          end
        rescue Object => e
          if alive
            logger.error "Unhandled listen loop exception #{e.inspect}."
            logger.error e.backtrace.join("\n")
          end
        end while alive = LISTENERS.first
      }
    end

  end
end
