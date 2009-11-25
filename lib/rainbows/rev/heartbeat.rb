# -*- encoding: binary -*-
module Rainbows
  module Rev

    # This class handles the Unicorn fchmod heartbeat mechanism
    # in Rev-based concurrency models to prevent the master
    # process from killing us unless we're blocked.  This class
    # will also detect and execute the graceful exit if triggered
    # by SIGQUIT
    class Heartbeat < ::Rev::TimerWatcher

      def on_timer
        if (ot = G.kato) > 0
          ot = Time.now - ot
          KATO.delete_if { |client, time| time < ot and client.timeout? }
        end
        exit if (! G.tick && CONN.size <= 0)
      end

    end
  end
end
