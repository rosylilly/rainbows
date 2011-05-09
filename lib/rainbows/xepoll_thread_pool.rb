# -*- encoding: binary -*-
require "thread"
require "sleepy_penguin"
require "raindrops"

module Rainbows::XEpollThreadPool
  include Rainbows::Base

  def init_worker_process(worker)
    super
    require "rainbows/xepoll_thread_pool/client"
    Rainbows::Client.__send__ :include, Client
  end

  def worker_loop(worker) # :nodoc:
    init_worker_process(worker)
    Client.loop
  end
end

