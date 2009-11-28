# -*- encoding: binary -*-

require 'actor'
module Rainbows

  # Actor concurrency model for Rubinius.  We can't seem to get message
  # passing working right, so we're throwing a Mutex into the mix for
  # now.  Hopefully somebody can fix things for us.
  #
  # This is different from the Revactor one which is not prone to race
  # conditions at all (since it uses Fibers).
  module ActorSpawn
    include Base

    # runs inside each forked worker, this sits around and waits
    # for connections and doesn't die until the parent dies (or is
    # given a INT, QUIT, or TERM signal)
    def worker_loop(worker)
      init_worker_process(worker)
      limit = worker_connections
      nr = 0

      # can't seem to get the message passing to work right at the moment :<
      lock = Mutex.new

      begin
        ret = IO.select(LISTENERS, nil, nil, 1) and ret.first.each do |l|
          lock.synchronize { nr >= limit } and break sleep(0.01)
          c = Rainbows.accept(l) and Actor.spawn do
            lock.synchronize { nr += 1 }
            begin
              process_client(c)
            ensure
              lock.synchronize { nr -= 1 }
            end
          end
        end
      rescue => e
        Error.listen_loop(e)
      end while G.tick || lock.synchronize { nr > 0 }
    end
  end
end
