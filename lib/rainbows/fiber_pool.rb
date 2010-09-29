# -*- encoding: binary -*-
require 'rainbows/fiber'

module Rainbows

  # A Fiber-based concurrency model for Ruby 1.9.  This uses a pool of
  # Fibers to handle client IO to run the application and the root Fiber
  # for scheduling and connection acceptance.  The pool size is equal to
  # the number of +worker_connections+.  Compared to the ThreadPool
  # model, Fibers are very cheap in terms of memory usage so you can
  # have more active connections.  This model supports a streaming
  # "rack.input" with lightweight concurrency.  Applications are
  # strongly advised to wrap all slow IO objects (sockets, pipes) using
  # the Rainbows::Fiber::IO class whenever possible.

  module FiberPool
    include Fiber::Base

    def worker_loop(worker) # :nodoc:
      init_worker_process(worker)
      pool = []
      worker_connections.times {
        ::Fiber.new {
          process_client(::Fiber.yield) while pool << ::Fiber.current
        }.resume # resume to hit ::Fiber.yield so it waits on a client
      }
      Fiber::Base.setup(self.class, app)

      begin
        schedule do |l|
          fib = pool.shift or break # let another worker process take it
          if io = l.kgio_tryaccept
            fib.resume(Fiber::IO.new(io, fib))
          else
            pool << fib
          end
        end
      rescue => e
        Error.listen_loop(e)
      end while G.alive || G.cur > 0
    end

  end
end
