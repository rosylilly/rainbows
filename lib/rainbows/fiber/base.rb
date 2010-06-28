# -*- encoding: binary -*-
require 'rainbows/fiber/io'

module Rainbows
  module Fiber

    # blocked readers (key: fileno, value: Rainbows::Fiber::IO object)
    RD = []

    # blocked writers (key: fileno, value: Rainbows::Fiber::IO object)
    WR = []

    # sleeping fibers go here (key: Fiber object, value: wakeup time)
    ZZ = {}.compare_by_identity

    # puts the current Fiber into uninterruptible sleep for at least
    # +seconds+.  Unlike Kernel#sleep, this it is not possible to sleep
    # indefinitely to be woken up (nobody wants that in a web server,
    # right?).  Calling this directly is deprecated, use
    # Rainbows.sleep(seconds) instead.
    def self.sleep(seconds)
      ZZ[::Fiber.current] = Time.now + seconds
      ::Fiber.yield
    end

    # base module used by FiberSpawn and FiberPool
    module Base
      include Rainbows::Base

      # the scheduler method that powers both FiberSpawn and FiberPool
      # concurrency models.  It times out idle clients and attempts to
      # schedules ones that were blocked on I/O.  At most it'll sleep
      # for one second (returned by the schedule_sleepers method) which
      # will cause it.
      def schedule(&block)
        ret = begin
          G.tick
          RD.compact.each { |c| c.f.resume } # attempt to time out idle clients
          t = schedule_sleepers
          Kernel.select(RD.compact.concat(LISTENERS),
                        WR.compact, nil, t) or return
        rescue Errno::EINTR
          retry
        rescue Errno::EBADF, TypeError
          LISTENERS.compact!
          raise
        end or return

        # active writers first, then _all_ readers for keepalive timeout
        ret[1].concat(RD.compact).each { |c| c.f.resume }

        # accept is an expensive syscall, filter out listeners we don't want
        (ret[0] & LISTENERS).each(&block)
      end

      # wakes up any sleepers that need to be woken and
      # returns an interval to IO.select on
      def schedule_sleepers
        max = nil
        now = Time.now
        fibs = []
        ZZ.delete_if { |fib, time|
          if now >= time
            fibs << fib
          else
            max = time
            false
          end
        }
        fibs.each { |fib| fib.resume }
        now = Time.now
        max.nil? || max > (now + 1) ? 1 : max - now
      end

      # TODO: IO.splice under Linux
      alias write_body_stream write_body_each

      # the sendfile 1.0.0+ gem includes IO#sendfile_nonblock
      if ::IO.method_defined?(:sendfile_nonblock)
        def write_body_path(client, body)
          file = Rainbows.body_to_io(body)
          if file.stat.file?
            sock, off = client.to_io, 0
            begin
              off += sock.sendfile_nonblock(file, off, 0x10000)
            rescue Errno::EAGAIN
              client.wait_writable
            rescue EOFError
              break
            rescue => e
              Rainbows::Error.app(e)
              break
            end while true
          else
            write_body_stream(client, body)
          end
        end
      else
        alias write_body write_body_each
      end

      def wait_headers_readable(client)
        io = client.to_io
        expire = nil
        begin
          return io.recv_nonblock(1, Socket::MSG_PEEK)
        rescue Errno::EAGAIN
          return if expire && expire < Time.now
          expire ||= Time.now + G.kato
          client.wait_readable
          retry
        end
      end

      def process_client(client)
        G.cur += 1
        super(client) # see Rainbows::Base
      ensure
        G.cur -= 1
        ZZ.delete(client.f)
      end

    end
  end
end
