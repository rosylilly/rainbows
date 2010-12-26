# -*- encoding: binary -*-
# :enddoc:
require 'rev'
Rev::VERSION >= '0.3.0' or abort 'rev >= 0.3.0 is required'
require 'rainbows/rev/heartbeat'
require 'rainbows/rev/server'
module Rainbows::Rev::Core
  include Rainbows::Base

  # runs inside each forked worker, this sits around and waits
  # for connections and doesn't die until the parent dies (or is
  # given a INT, QUIT, or TERM signal)
  def worker_loop(worker)
    Rainbows::Response.setup(Rainbows::Rev::Client)
    require 'rainbows/rev/sendfile'
    Rainbows::Rev::Client.__send__(:include, Rainbows::Rev::Sendfile)
    init_worker_process(worker)
    mod = Rainbows.const_get(@use)
    rloop = Rainbows::Rev::Server.const_set(:LOOP, ::Rev::Loop.default)
    Rainbows::Rev::Client.const_set(:LOOP, rloop)
    Rainbows::Rev::Server.const_set(:MAX, @worker_connections)
    Rainbows::Rev::Server.const_set(:CL, mod.const_get(:Client))
    Rainbows::EvCore.const_set(:APP, G.server.app)
    Rainbows::EvCore.setup
    Rainbows::Rev::Heartbeat.new(1, true).attach(rloop)
    LISTENERS.map! { |s| Rainbows::Rev::Server.new(s).attach(rloop) }
    rloop.run
  end
end
