# -*- encoding: binary -*-
require 'unicorn'

module Rainbows

  # global vars because class/instance variables are confusing me :<
  # this struct is only accessed inside workers and thus private to each
  # G.cur may not be used in the network concurrency model
  class State < Struct.new(:alive,:m,:cur,:kato,:server,:tmp)
    def tick
      tmp.chmod(self.m = m == 0 ? 1 : 0)
      alive && server.master_pid == Process.ppid or quit!
    end

    def quit!
      self.alive = false
      server.class.const_get(:LISTENERS).map! { |s| s.close rescue nil }
      false
    end
  end
  G = State.new(true, 0, 0, 2)

  require 'rainbows/const'
  require 'rainbows/http_server'
  require 'rainbows/http_response'
  require 'rainbows/base'
  autoload :AppPool, 'rainbows/app_pool'
  autoload :DevFdResponse, 'rainbows/dev_fd_response'

  class << self

    # runs the Rainbows! HttpServer with +app+ and +options+ and does
    # not return until the server has exited.
    def run(app, options = {})
      HttpServer.new(app, options).start.join
    end
  end

  # configures \Rainbows! with a given concurrency model to +use+ and
  # a +worker_connections+ upper-bound.  This method may be called
  # inside a Unicorn/Rainbows configuration file:
  #
  #   Rainbows! do
  #     use :Revactor # this may also be :ThreadSpawn or :ThreadPool
  #     worker_connections 400
  #     keepalive_timeout 0 # zero disables keepalives entirely
  #   end
  #
  #   # the rest of the Unicorn configuration
  #   worker_processes 8
  #
  # See the documentation for the respective Revactor, ThreadSpawn,
  # and ThreadPool classes for descriptions and recommendations for
  # each of them.  The total number of clients we're able to serve is
  # +worker_processes+ * +worker_connections+, so in the above example
  # we can serve 8 * 400 = 3200 clients concurrently.
  #
  # The default is +keepalive_timeout+ is 2 seconds, which should be
  # enough under most conditions for browsers to render the page and
  # start retrieving extra elements for.  Increasing this beyond 5
  # seconds is not recommended.  Zero disables keepalive entirely
  # (but pipelining fully-formed requests is still works).
  def Rainbows!(&block)
    block_given? or raise ArgumentError, "Rainbows! requires a block"
    HttpServer.setup(block)
  end

  # maps models to default worker counts, default worker count numbers are
  # pretty arbitrary and tuning them to your application and hardware is
  # highly recommended
  MODEL_WORKER_CONNECTIONS = {
    :Base => 1, # this one can't change
    :Revactor => 50,
    :ThreadSpawn => 30,
    :ThreadPool => 10,
    :Rev => 50,
    :RevThreadSpawn => 50,
    :EventMachine => 50,
    :FiberSpawn => 50,
    :FiberPool => 50,
  }.each do |model, _|
    u = model.to_s.gsub(/([a-z0-9])([A-Z0-9])/) { "#{$1}_#{$2.downcase!}" }
    autoload model, "rainbows/#{u.downcase!}"
  end
  autoload :Fiber, 'rainbows/fiber' # core class

end

# inject the Rainbows! method into Unicorn::Configurator
Unicorn::Configurator.class_eval { include Rainbows }
