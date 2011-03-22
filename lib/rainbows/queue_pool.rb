# -*- encoding: binary -*-
# :enddoc:
require 'thread'

# Thread pool class based on pulling off a single Ruby Queue.
# This is NOT used for the ThreadPool class, since that class does not
# need a userspace Queue.
class Rainbows::QueuePool
  attr_reader :queue

  def initialize(size = 20)
    q = Queue.new
    @threads = (1..size).map do
      Thread.new do
        while job = q.shift
          yield job
        end
      end
    end
    @queue = q
  end

  def quit!
    @threads.each { |_| @queue << nil }
    @threads.delete_if do |t|
      Rainbows.tick
      t.alive? ? t.join(0.01) : true
    end until @threads.empty?
  end
end
