# -*- encoding: binary -*-
require 'rev'
Rev::VERSION >= '0.3.0' or abort 'rev >= 0.3.0 is required'

module Rainbows
  module Rev

    # This class handles the Unicorn fchmod heartbeat mechanism
    # in Rev-based concurrency models to prevent the master
    # process from killing us unless we're blocked.  This class
    # will also detect and execute the graceful exit if triggered
    # by SIGQUIT
    class Heartbeat < ::Rev::TimerWatcher
      # +tmp+ must be a +File+ that responds to +chmod+
      def initialize(tmp)
        @m, @tmp = 0, tmp
        super(1, true)
      end

      def on_timer
        @tmp.chmod(@m = 0 == @m ? 1 : 0)
        exit if (! G.alive && G.cur <= 0)
      end

    end
  end
end
