# -*- encoding: binary -*-
# :enddoc:
# This module only gets loaded on shutdown
module Rainbows::JoinThreads

  # blocking acceptor threads must be forced to run
  def self.acceptors(threads)
    expire = Time.now + Rainbows.server.timeout
    threads.delete_if do |thr|
      Rainbows.tick
      begin
        # blocking accept() may not wake up properly
        thr.raise(Errno::EINTR) if Time.now > expire && thr.stop?

        thr.run
        thr.join(0.01)
      rescue
        true
      end
    end until threads.empty?
  end
end
