# -*- encoding: binary -*-

module Rainbows::XEpollThreadSpawn
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
end
