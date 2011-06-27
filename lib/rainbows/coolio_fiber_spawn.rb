# -*- encoding: binary -*-
require 'rainbows/fiber/coolio'

# A combination of the Coolio and FiberSpawn models.
#
# This concurrency model is difficult to use with existing applications,
# lacks third-party support, and is thus NOT recommended.
#
# This allows Ruby 1.9 Fiber-based concurrency for application
# processing while exposing a synchronous execution model and using
# scalable network concurrency provided by Cool.io.  A streaming
# "rack.input" is exposed.  Applications are strongly advised to wrap
# all slow IO objects (sockets, pipes) using the Rainbows::Fiber::IO or
# a Cool.io-compatible class whenever possible.
module Rainbows::CoolioFiberSpawn

  include Rainbows::Base
  include Rainbows::Fiber::Coolio

  def worker_loop(worker) # :nodoc:
    Rainbows::Response.setup
    init_worker_process(worker)
    Server.const_set(:MAX, @worker_connections)
    Rainbows::Fiber::Base.setup(Server, nil)
    Server.const_set(:APP, Rainbows.server.app)
    Heartbeat.new(1, true).attach(Coolio::Loop.default)
    LISTENERS.map! { |s| Server.new(s).attach(Coolio::Loop.default) }
    Rainbows::Client.__send__ :include, Rainbows::Fiber::Coolio::Methods
    Coolio::Loop.default.run
  end
end
