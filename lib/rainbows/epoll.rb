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
module Rainbows::Epoll
  # :stopdoc:
  include Rainbows::Base
  ReRun = []
  autoload :Server, 'rainbows/epoll/server'
  autoload :Client, 'rainbows/epoll/client'
  autoload :ResponsePipe, 'rainbows/epoll/response_pipe'
  autoload :ResponseChunkPipe, 'rainbows/epoll/response_chunk_pipe'
  class << self
    attr_writer :nr_clients
  end

  def self.loop
    begin
      EP.wait(nil, 1000) { |_, obj| obj.epoll_run }
      while obj = ReRun.shift
        obj.epoll_run
      end
      Rainbows::Epoll::Client.expire
    rescue Errno::EINTR
    rescue => e
      Rainbows::Error.listen_loop(e)
    end while Rainbows.tick || @nr_clients.call > 0
  end

  def init_worker_process(worker)
    super
    Rainbows::Epoll.const_set :EP, SleepyPenguin::Epoll.new
    Rainbows.at_quit { Rainbows::Epoll::EP.close }
    Rainbows::Client.__send__ :include, Client
  end

  def worker_loop(worker) # :nodoc:
    init_worker_process(worker)
    Server.run
  end
  # :startdoc:
end
