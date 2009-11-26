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
      fio = Rainbows::Fiber::IO

      begin
        schedule do |l|
          break if G.cur >= limit
          io = begin
            l.accept_nonblock
          rescue Errno::EAGAIN, Errno::ECONNABORTED
            next
          end
          ::Fiber.new { process_client(fio.new(io, ::Fiber.current)) }.resume
        end
      rescue => e
        Error.listen_loop(e)
      end while G.alive || G.cur > 0
    end

  end
end
