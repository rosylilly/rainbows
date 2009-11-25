# -*- encoding: binary -*-
require 'rainbows/fiber'
require 'pp'

module Rainbows

  # A Fiber-based concurrency model for Ruby 1.9.  This uses a pool of
  # Fibers to handle client IO to run the application and the root Fiber
  # for scheduling and connection acceptance.  The pool size is equal to
  # the number of +worker_connections+.  This model supports a streaming
  # "rack.input" with lightweight concurrency.  Applications are
  # strongly advised to wrap slow all IO objects (sockets, pipes) using
  # the Rainbows::Fiber::IO class whenever possible.

  module FiberPool
    include Fiber::Base

    def worker_loop(worker)
      init_worker_process(worker)
      pool = []
      worker_connections.times {
        ::Fiber.new {
          process_client(::Fiber.yield) while pool << ::Fiber.current
        }.resume # resume to hit ::Fiber.yield so it waits on a client
      }
      Fiber::Base.const_set(:APP, app)
      rd = Fiber::RD
      wr = Fiber::WR

      begin
        ret = begin
          G.tick
          IO.select(rd.keys.concat(LISTENERS), wr.keys, nil, 1) or next
        rescue Errno::EINTR
          retry
        rescue Errno::EBADF, TypeError
          LISTENERS.compact!
          G.cur > 0 ? retry : break
        end

        # active writers first, then _all_ readers for keepalive timeout
        ret[1].concat(rd.keys).each { |c| c.f.resume }

        # accept() is an expensive syscall
        (ret.first & LISTENERS).each do |l|
          fib = pool.shift or break
          io = begin
            l.accept_nonblock
          rescue Errno::EAGAIN, Errno::ECONNABORTED
            pool << fib
            next
          end
          fib.resume(Fiber::IO.new(io, fib))
        end
      rescue => e
        listen_loop_error(e)
      end while G.alive || G.cur > 0
    end

  end
end
