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
      nr = 0
      limit = worker_connections

      # closing anything we IO.select on will raise EBADF
      trap(:USR1) { reopen_worker_logs(worker.nr) rescue nil }
      trap(:QUIT) { alive = false; LISTENERS.map! { |s| s.close rescue nil } }
      [:TERM, :INT].each { |sig| trap(sig) { exit(0) } } # instant shutdown
      logger.info "worker=#{worker.nr} ready with ThreadSpawn"

      while alive && master_pid == Process.ppid
        ret = begin
          IO.select(LISTENERS, nil, nil, timeout/2.0) or next
        rescue Errno::EINTR
          retry
        rescue Errno::EBADF
          alive = false
        end

        ret.first.each do |l|
          while threads.list.size >= limit
            nuke_old_thread(threads)
          end
          c = begin
            l.accept_nonblock
          rescue Errno::EINTR, Errno::ECONNABORTED
            next
          end
          threads.add(Thread.new(c) { |c|
            Thread.current[:t] = Time.now
            process_client(c)
          })
        end
      end
      join_spawned_threads(threads)
    end

    def nuke_old_thread(threads)
      threads.list.each do |thr|
        next if (Time.now - (thr[:t] || next)) < timeout
        thr.kill
        logger.error "killed #{thr.inspect} for being too old"
        return
      end
      # nothing to kill, yield to another thread
      Thread.pass
    end

    def join_spawned_threads(threads)
      logger.info "Joining spawned threads..."
      t0 = Time.now
      timeleft = timeout
      threads.list.each { |thr|
        thr.join(timeleft)
        timeleft -= (Time.now - t0)
      }
      logger.info "Done joining spawned threads."
    end

  end
end
