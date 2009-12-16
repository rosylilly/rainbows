# -*- encoding: binary -*-
require 'rev'
Rev::VERSION >= '0.3.0' or abort 'rev >= 0.3.0 is required'
require 'rainbows/rev/heartbeat'

module Rainbows
  module Rev
    class Server < ::Rev::IO
      G = Rainbows::G
      # CL and MAX will be defined in the corresponding worker loop

      def on_readable
        return if CONN.size >= MAX
        io = Rainbows.accept(@_io) and CL.new(io).attach(LOOP)
      end
    end # class Server

    module Core
      include Base

      # runs inside each forked worker, this sits around and waits
      # for connections and doesn't die until the parent dies (or is
      # given a INT, QUIT, or TERM signal)
      def worker_loop(worker)
        init_worker_process(worker)
        mod = self.class.const_get(@use)
        rloop = Server.const_set(:LOOP, ::Rev::Loop.default)
        Server.const_set(:MAX, @worker_connections)
        Server.const_set(:CL, mod.const_get(:Client))
        EvCore.const_set(:APP, G.server.app)
        Heartbeat.new(1, true).attach(rloop)
        LISTENERS.map! { |s| Server.new(s).attach(rloop) }
        rloop.run
      end

    end # module Core
  end # module Rev
end # module Rainbows
