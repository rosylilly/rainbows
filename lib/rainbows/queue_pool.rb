# -*- encoding: binary -*-
# :enddoc:
require 'thread'

module Rainbows

  # Thread pool class based on pulling off a single Ruby Queue.
  # This is NOT used for the ThreadPool class, since that class does not
  # need a userspace Queue.
  class QueuePool < Struct.new(:queue, :threads)
    G = Rainbows::G

    def initialize(size = 20, &block)
      q = Queue.new
      self.threads = (1..size).map do
        Thread.new do
          while job = q.shift
            block.call(job)
          end
        end
      end
      self.queue = q
    end

    def quit!
      threads.each { |_| queue << nil }
      threads.delete_if do |t|
        G.tick
        t.alive? ? t.join(0.01) : true
      end until threads.empty?
    end
  end
end
