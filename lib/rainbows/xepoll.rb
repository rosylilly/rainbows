# -*- encoding: binary -*-
require 'raindrops'
require 'rainbows/epoll'

# Edge-triggered epoll concurrency model with blocking accept() in a
# (hopefully) native thread.  This is just like Epoll, but recommended
# for Ruby 1.9 users as it can avoid accept()-scalability issues on
# multicore machines with many worker processes.
#
# === RubyGem Requirements
#
# * raindrops 0.6.0 or later
# * sleepy_penguin 3.0.1 or later
# * sendfile 1.1.0 or later
module Rainbows::XEpoll
  # :stopdoc:
  include Rainbows::Base
  autoload :Client, 'rainbows/xepoll/client'

  def init_worker_process(worker)
    super
    Rainbows.const_set(:EP, SleepyPenguin::Epoll.new)
    Rainbows::Client.__send__ :include, Client
  end

  def worker_loop(worker) # :nodoc:
    init_worker_process(worker)
    Client.loop
  end
  # :startdoc:
end
