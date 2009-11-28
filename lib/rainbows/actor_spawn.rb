# -*- encoding: binary -*-

require 'actor'
module Rainbows
  module ActorSpawn
    include Base

    # runs inside each forked worker, this sits around and waits
    # for connections and doesn't die until the parent dies (or is
    # given a INT, QUIT, or TERM signal)
    def worker_loop(worker)
      init_worker_process(worker)
      limit = worker_connections
      root = Actor.current
      clients = {}

      # ticker
      Actor.spawn do
        while true
          sleep 1
          G.tick
        end
      end

      listeners = LISTENERS.map do |s|
        Actor.spawn(s) do |l|
          begin
            while clients.size >= limit
              logger.info "busy: clients=#{clients.size} >= limit=#{limit}"
              Actor.receive { |filter| filter.when(:resume) {} }
            end
            Actor.spawn(l.accept) do |c|
              clients[Actor.current] = false
              begin
                process_client(c)
              ensure
                root << Actor.current
              end
            end
          rescue Errno::EAGAIN, Errno::ECONNABORTED
          rescue => e
            Error.listen_loop(e)
          end while G.alive
        end
      end

      begin
        Actor.receive do |filter|
          filter.when(Actor) do |actor|
            orig = clients.size
            clients.delete(actor)
            orig >= limit and listeners.each { |l| l << :resume }
          end
        end
      end while G.alive || clients.size > 0
    end
  end
end
