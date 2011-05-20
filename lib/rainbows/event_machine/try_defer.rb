# -*- encoding: binary -*-

# Middleware that will run the app dispatch in a separate thread.
# This middleware is automatically loaded by Rainbows! when using
# EventMachine and if the app responds to the +deferred?+ method.
#
# Use EM.threadpool_size in your \Rainbows! config file to control
# the number of threads used by EventMachine.
#
# See http://brainspl.at/articles/2008/04/18/deferred-requests-with-merb-ebb-and-thin
# for more information.
class Rainbows::EventMachine::TryDefer
  # shortcuts
  ASYNC_CALLBACK = Rainbows::EvCore::ASYNC_CALLBACK # :nodoc:

  def initialize(app) # :nodoc:
    # the entire app becomes multithreaded, even the root (non-deferred)
    # thread since any thread can share processes with others
    Rainbows::Const::RACK_DEFAULTS['rack.multithread'] = true
    @app = app
  end

  def call(env) # :nodoc:
    if @app.deferred?(env)
      EM.defer(proc { catch(:async) { @app.call(env) } }, env[ASYNC_CALLBACK])
      # all of the async/deferred stuff breaks Rack::Lint :<
      nil
    else
      @app.call(env)
    end
  end
end
