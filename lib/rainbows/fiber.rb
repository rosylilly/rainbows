# -*- encoding: binary -*-
# :enddoc:
begin
  require 'fiber'
rescue LoadError
  defined?(NeverBlock) or raise
end

# core namespace for all things that use Fibers in \Rainbows!
#
# It's generally not recommended to use any of this in your applications
# unless you're willing to accept breakage.  Most of this is very
# difficult-to-use, fragile and we don't have much time to devote to
# supporting these in the future.
module Rainbows::Fiber

  # blocked readers (key: fileno, value: Rainbows::Fiber::IO object)
  RD = []

  # blocked writers (key: fileno, value: Rainbows::Fiber::IO object)
  WR = []

  # sleeping fibers go here (key: Fiber object, value: wakeup time)
  ZZ = {}

  # puts the current Fiber into uninterruptible sleep for at least
  # +seconds+.  Unlike Kernel#sleep, this it is not possible to sleep
  # indefinitely to be woken up (nobody wants that in a web server,
  # right?).  Calling this directly is deprecated, use
  # Rainbows.sleep(seconds) instead.
  def self.sleep(seconds)
    ZZ[Fiber.current] = Time.now + seconds
    Fiber.yield
  end

  autoload :Base, 'rainbows/fiber/base'
  autoload :Queue, 'rainbows/fiber/queue'
  autoload :IO, 'rainbows/fiber/io'
end
