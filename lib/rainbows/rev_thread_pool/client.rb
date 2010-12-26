# -*- encoding: binary -*-
# :enddoc:
class Rainbows::RevThreadPool::Client < Rainbows::Rev::ThreadClient
  # QUEUE constant will be set in worker_loop
  def app_dispatch
    QUEUE << self
  end
end
