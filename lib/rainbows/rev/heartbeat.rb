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
        exit if (! G.tick && G.cur <= 0)
      end

    end
  end
end
