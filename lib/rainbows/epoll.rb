# -*- encoding: binary -*-
# :enddoc:
require 'sleepy_penguin'
require 'sendfile'

# Edge-triggered epoll concurrency model.  This is extremely unfair
# and optimized for throughput at the expense of fairness
module Rainbows::Epoll
  include Rainbows::Base
  autoload :State, 'rainbows/epoll/state'
  autoload :Server, 'rainbows/epoll/server'
  autoload :Client, 'rainbows/epoll/client'
  autoload :ResponsePipe, 'rainbows/epoll/response_pipe'
  autoload :ResponseChunkPipe, 'rainbows/epoll/response_chunk_pipe'

  def worker_loop(worker) # :nodoc:
    init_worker_process(worker)
    Rainbows::EvCore.setup
    Rainbows::Client.__send__ :include, Client
    Server.run
  end
end
