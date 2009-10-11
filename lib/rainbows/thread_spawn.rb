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

      # closing anything we IO.select on will raise EBADF
      trap(:USR1) { reopen_worker_logs(worker.nr) rescue nil }
      trap(:QUIT) { LISTENERS.map! { |s| s.close rescue nil } }
      [:TERM, :INT].each { |sig| trap(sig) { exit(0) } } # instant shutdown
      logger.info "worker=#{worker.nr} ready with ThreadSpawn"

      begin
        ret = begin
          alive.chmod(m = 0 == m ? 1 : 0)
          IO.select(LISTENERS, nil, nil, timeout/2.0) or next
        rescue Errno::EINTR
          retry
        rescue Errno::EBADF
          break
        end

        ret.first.each do |l|
          nuke_old_thread(threads, limit)
          c = begin
            l.accept_nonblock
          rescue Errno::EAGAIN, Errno::ECONNABORTED
            next
          end
          threads.add(Thread.new(c) { |c| process_client(c) })
        end
      rescue Object => e
        listen_loop_error(e) if alive
      end while alive && master_pid == Process.ppid
      join_spawned_threads(threads)
    end

    def nuke_old_thread(threads, limit)
      while (list = threads.list).size > limit
        list.each do |thr|
          thr.alive? or return # it _just_ died, we don't need it
          next if (age = (Time.now - (thr[:t] || next))) < timeout
          thr.kill # no-op if already dead
          logger.error "killed #{thr.inspect} for being too old: #{age}"
          return
        end
        # nothing to kill, yield to another thread
        Thread.pass
      end
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
