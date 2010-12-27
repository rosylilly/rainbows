# -*- encoding: binary -*-

# CoolioThreadPool is the new version of this, use that instead.
#
# A combination of the Rev and ThreadSpawn models.  This allows Ruby
# Thread-based concurrency for application processing.  It DOES NOT
# expose a streamable "rack.input" for upload processing within the
# app.  DevFdResponse should be used with this class to proxy
# asynchronous responses.  All network I/O between the client and
# server are handled by the main thread and outside of the core
# application dispatch.
#
# Unlike ThreadSpawn, Rev makes this model highly suitable for
# slow clients and applications with medium-to-slow response times
# (I/O bound), but less suitable for sleepy applications.
#
# This concurrency model is designed for Ruby 1.9, and Ruby 1.8
# users are NOT advised to use this due to high CPU usage.
module Rainbows::RevThreadSpawn
  include Rainbows::Rev::Core

  def init_worker_process(worker) # :nodoc:
    super
    master = Rainbows::Rev::Master.new(Queue.new).attach(Rev::Loop.default)
    Rainbows::RevThreadSpawn::Client.const_set(:MASTER, master)
  end
end
# :enddoc:
require 'rainbows/rev_thread_spawn/client'
