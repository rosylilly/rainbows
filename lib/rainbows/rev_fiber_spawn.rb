# -*- encoding: binary -*-
require 'rainbows/fiber/rev'

module Rainbows

  # A combination of the Rev and FiberSpawn models.  This allows Ruby
  # 1.9 Fiber-based concurrency for application processing while
  # exposing a synchronous execution model and using scalable network
  # concurrency provided by Rev.  A "rack.input" is exposed as well
  # being Sunshowers-compatible.  Applications are strongly advised to
  # wrap all slow IO objects (sockets, pipes) using the
  # Rainbows::Fiber::IO or similar class whenever possible.
  module RevFiberSpawn

    include Base
    include Fiber::Rev

    def worker_loop(worker)
      init_worker_process(worker)
      Server.const_set(:MAX, @worker_connections)
      Server.const_set(:APP, G.server.app)
      Heartbeat.new(1, true).attach(::Rev::Loop.default)
      kato = Kato.new.attach(::Rev::Loop.default)
      Rainbows::Fiber::IO.const_set(:KATO, kato)
      LISTENERS.map! { |s| Server.new(s).attach(::Rev::Loop.default) }
      ::Rev::Loop.default.run
    end
  end
end
