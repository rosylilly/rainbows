# -*- encoding: binary -*-
require 'sleepy_penguin'
require 'sendfile'

# Edge-triggered epoll concurrency model using
# {sleepy_penguin}[http://bogomips.org/sleepy_penguin/] for epoll.
#
# Unlike more portable options like Coolio and EventMachine, this
# is Linux-only, but uses edge-triggering instead of level-triggering,
# so it may perform better in some cases.  Coolio and EventMachine have
# better library support and may be widely-used, however.
#
# Consider using XEpoll instead of this if you are using Ruby 1.9,
# it will avoid accept()-scalability issues with many worker processes.
#
# When serving static files, this is extremely unfair and optimized
# for throughput at the expense of fairness.  This is not an issue
# if you're not serving static files, or if your working set is
# small enough to aways be in your kernel page cache.  This concurrency
# model may starve clients if you have slow disks and large static files.
#
# === RubyGem Requirements
#
# * raindrops 0.6.0 or later
# * sleepy_penguin 3.0.1 or later
# * sendfile 1.1.0 or later
#
module Rainbows::Epoll
  # :stopdoc:
  include Rainbows::Base
  autoload :Server, 'rainbows/epoll/server'
  autoload :Client, 'rainbows/epoll/client'
  autoload :ResponsePipe, 'rainbows/epoll/response_pipe'
  autoload :ResponseChunkPipe, 'rainbows/epoll/response_chunk_pipe'

  def init_worker_process(worker)
    super
    Rainbows.const_set(:EP, SleepyPenguin::Epoll.new)
    Rainbows::Client.__send__ :include, Client
    LISTENERS.each { |io| io.extend(Server) }
  end

  def worker_loop(worker) # :nodoc:
    init_worker_process(worker)
    Client.loop
  end
  # :startdoc:
end
