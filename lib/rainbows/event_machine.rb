# -*- encoding: binary -*-
require 'eventmachine'
EM::VERSION >= '0.12.10' or abort 'eventmachine 0.12.10 is required'

# Implements a basic single-threaded event model with
# {EventMachine}[http://rubyeventmachine.com/].  It is capable of
# handling thousands of simultaneous client connections, but with only
# a single-threaded app dispatch.  It is suited for slow clients,
# and can work with slow applications via asynchronous libraries such as
# {async_sinatra}[http://github.com/raggi/async_sinatra],
# {Cramp}[http://cramp.in/],
# and {rack-fiber_pool}[http://github.com/mperham/rack-fiber_pool].
#
# It does not require your Rack application to be thread-safe,
# reentrancy is only required for the DevFdResponse body
# generator.
#
# Compatibility: Whatever \EventMachine ~> 0.12.10 and Unicorn both
# support, currently Ruby 1.8/1.9.
#
# This model is compatible with users of "async.callback" in the Rack
# environment such as
# {async_sinatra}[http://github.com/raggi/async_sinatra].
#
# For a complete asynchronous framework,
# {Cramp}[http://cramp.in/] is fully
# supported when using this concurrency model.
#
# This model is fully-compatible with
# {rack-fiber_pool}[http://github.com/mperham/rack-fiber_pool]
# which allows each request to run inside its own \Fiber after
# all request processing is complete.
#
# Merb (and other frameworks/apps) supporting +deferred?+ execution as
# documented at Rainbows::EventMachine::TryDefer
#
# This model does not implement as streaming "rack.input" which allows
# the Rack application to process data as it arrives.  This means
# "rack.input" will be fully buffered in memory or to a temporary file
# before the application is entered.
#
# === RubyGem Requirements
#
# * event_machine 0.12.10
module Rainbows::EventMachine
  autoload :ResponsePipe, 'rainbows/event_machine/response_pipe'
  autoload :ResponseChunkPipe, 'rainbows/event_machine/response_chunk_pipe'
  autoload :TryDefer, 'rainbows/event_machine/try_defer'
  autoload :Client, 'rainbows/event_machine/client'

  include Rainbows::Base

  # Cramp (and possibly others) can subclass Rainbows::EventMachine::Client
  # and provide the :em_client_class option.  We /don't/ want to load
  # Rainbows::EventMachine::Client in the master process since we need
  # reloadability.
  def em_client_class
    case klass = Rainbows::O[:em_client_class]
    when Proc
      klass.call # e.g.: proc { Cramp::WebSocket::Rainbows }
    when Symbol, String
      eval(klass.to_s) # Object.const_get won't resolve multi-level paths
    else # @use should be either :EventMachine or :NeverBlock
      Rainbows.const_get(@use).const_get(:Client)
    end
  end

  # runs inside each forked worker, this sits around and waits
  # for connections and doesn't die until the parent dies (or is
  # given a INT, QUIT, or TERM signal)
  def worker_loop(worker) # :nodoc:
    init_worker_process(worker)
    server = Rainbows.server
    server.app.respond_to?(:deferred?) and
      server.app = TryDefer.new(server.app)

    # enable them both, should be non-fatal if not supported
    EM.epoll
    EM.kqueue
    logger.info "#@use: epoll=#{EM.epoll?} kqueue=#{EM.kqueue?}"
    client_class = em_client_class
    max = worker_connections + LISTENERS.size
    Rainbows::EventMachine::Server.const_set(:MAX, max)
    Rainbows::EventMachine::Server.const_set(:CL, client_class)
    Rainbows::EventMachine::Client.const_set(:APP, Rainbows.server.app)
    EM.run {
      conns = EM.instance_variable_get(:@conns) or
        raise RuntimeError, "EM @conns instance variable not accessible!"
      Rainbows::EventMachine::Server.const_set(:CUR, conns)
      Rainbows.at_quit do
        EM.next_tick { conns.each_value { |c| client_class === c and c.quit } }
      end
      EM.add_periodic_timer(1) do
        EM.stop if ! Rainbows.tick && conns.empty? && EM.reactor_running?
      end
      LISTENERS.map! do |s|
        EM.watch(s, Rainbows::EventMachine::Server) do |c|
          c.notify_readable = true
        end
      end
    }
  end
end
# :enddoc:
require 'rainbows/event_machine/server'
