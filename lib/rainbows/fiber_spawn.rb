# -*- encoding: binary -*-
require 'rainbows/fiber'

module Rainbows

  # Simple Fiber-based concurrency model for 1.9.  This spawns a new
  # Fiber for every incoming client connection and the root Fiber for
  # scheduling and connection acceptance.  This exports a streaming
  # "rack.input" with lightweight concurrency.  Applications are
  # strongly advised to wrap all slow IO objects (sockets, pipes) using
  # the Rainbows::Fiber::IO class whenever possible.

  module FiberSpawn
    include Fiber::Base

    def worker_loop(worker)
      init_worker_process(worker)
      Fiber::Base.const_set(:APP, app)
      limit = worker_connections
      rd = Rainbows::Fiber::RD
      wr = Rainbows::Fiber::WR
      fio = Rainbows::Fiber::IO

      begin
        ret = begin
          IO.select(rd.keys.concat(LISTENERS), wr.keys, nil, 1) or next
        rescue Errno::EINTR
          G.tick
          retry
        rescue Errno::EBADF, TypeError
          LISTENERS.compact!
          G.cur > 0 ? retry : break
        end
        G.tick

        # active writers first, then _all_ readers for keepalive timeout
        ret[1].concat(rd.keys).each { |c| c.f.resume }
        G.tick

        # accept() is an expensive syscall
        (ret.first & LISTENERS).each do |l|
          break if G.cur >= limit
          io = begin
            l.accept_nonblock
          rescue Errno::EAGAIN, Errno::ECONNABORTED
            next
          end
          ::Fiber.new { process_client(fio.new(io, ::Fiber.current)) }.resume
        end
        G.tick
      rescue => e
        listen_loop_error(e)
      end while G.tick || G.cur > 0
    end

  end
end
