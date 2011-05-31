# -*- encoding: binary -*-
require "thread"
require "sleepy_penguin"
require "raindrops"

# This is an edge-triggered epoll concurrency model with blocking
# accept() in a (hopefully) native thread.  This is comparable to
# ThreadSpawn and CoolioThreadSpawn, but is Linux-only and able to exploit
# "wake one" accept() behavior of a blocking accept() call when used
# with native threads.
#
# This supports streaming "rack.input" and allows +:pool_size+ tuning
# independently of +worker_connections+
#
# === Disadvantages
#
# This is only supported under Linux 2.6 and later kernels.
#
# === Compared to CoolioThreadSpawn
#
# This does not buffer outgoing responses in userspace at all, meaning
# it can lower response latency to fast clients and also prevent
# starvation of other clients when reading slow disks for responses
# (when combined with native threads).
#
# CoolioThreadSpawn is likely better for trickling large static files or
# proxying responses to slow clients, but this is likely better for fast
# clients.
#
# Unlikely CoolioThreadSpawn, this supports streaming "rack.input" which
# is useful for reading large uploads from fast clients.
#
# === Compared to ThreadSpawn
#
# This can maintain idle connections without the memory overhead of an
# idle Thread.  The cost of handling/dispatching active connections is
# exactly the same for an equivalent number of active connections.
#
# === RubyGem Requirements
#
# * raindrops 0.6.0 or later
# * sleepy_penguin 3.0.1 or later
module Rainbows::XEpollThreadSpawn
  # :stopdoc:
  include Rainbows::Base

  def init_worker_process(worker)
    super
    require "rainbows/xepoll_thread_spawn/client"
    Rainbows::Client.__send__ :include, Client
  end

  def worker_loop(worker) # :nodoc:
    init_worker_process(worker)
    Client.loop
  end
  # :startdoc:
end
