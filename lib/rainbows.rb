# -*- encoding: binary -*-
require 'kgio'
require 'unicorn'
# the value passed to TCP_DEFER_ACCEPT actually matters in Linux 2.6.32+
Unicorn::SocketHelper::DEFAULTS[:tcp_defer_accept] = 60

module Rainbows

  # global vars because class/instance variables are confusing me :<
  # this struct is only accessed inside workers and thus private to each
  # G.cur may not be used in the network concurrency model
  # :stopdoc:
  class State < Struct.new(:alive,:m,:cur,:kato,:server,:tmp,:expire)
    def tick
      tmp.chmod(self.m = m == 0 ? 1 : 0)
      exit!(2) if expire && Time.now >= expire
      alive && server.master_pid == Process.ppid or quit!
    end

    def quit!
      self.alive = false
      Rainbows::HttpParser.quit
      self.expire ||= Time.now + (server.timeout * 2.0)
      server.class.const_get(:LISTENERS).map! { |s| s.close rescue nil }
      false
    end
  end
  G = State.new(true, 0, 0, 5)
  O = {}
  class Response416 < RangeError; end

  # map of numeric file descriptors to IO objects to avoid using IO.new
  # and potentially causing race conditions when using /dev/fd/
  FD_MAP = {}
  FD_MAP.compare_by_identity if FD_MAP.respond_to?(:compare_by_identity)

  # :startdoc:

  require 'rainbows/const'
  require 'rainbows/http_parser'
  require 'rainbows/http_server'
  require 'rainbows/response'
  require 'rainbows/client'
  require 'rainbows/process_client'
  autoload :Base, 'rainbows/base'
  autoload :Sendfile, 'rainbows/sendfile'
  autoload :AppPool, 'rainbows/app_pool'
  autoload :DevFdResponse, 'rainbows/dev_fd_response'
  autoload :MaxBody, 'rainbows/max_body'
  autoload :QueuePool, 'rainbows/queue_pool'
  autoload :EvCore, 'rainbows/ev_core'
  autoload :SocketProxy, 'rainbows/socket_proxy'

  class << self

    # Sleeps the current application dispatch.  This will pick the
    # optimal method to sleep depending on the concurrency model chosen
    # (which may still suck and block the entire process).  Using this
    # with the basic :Coolio or :EventMachine models is not recommended.
    # This should be used within your Rack application.
    def sleep(nr)
      case G.server.use
      when :FiberPool, :FiberSpawn
        Rainbows::Fiber.sleep(nr)
      when :RevFiberSpawn, :CoolioFiberSpawn
        Rainbows::Fiber::Coolio::Sleeper.new(nr)
      when :Revactor
        Actor.sleep(nr)
      else
        Kernel.sleep(nr)
      end
    end

    # runs the Rainbows! HttpServer with +app+ and +options+ and does
    # not return until the server has exited.
    def run(app, options = {}) # :nodoc:
      HttpServer.new(app, options).start.join
    end

    # :stopdoc:
    # the default max body size is 1 megabyte (1024 * 1024 bytes)
    @@max_bytes = 1024 * 1024

    def max_bytes; @@max_bytes; end
    def max_bytes=(nr); @@max_bytes = nr; end
    # :startdoc:
  end

  # :stopdoc:
  # maps models to default worker counts, default worker count numbers are
  # pretty arbitrary and tuning them to your application and hardware is
  # highly recommended
  MODEL_WORKER_CONNECTIONS = {
    :Base => 1, # this one can't change
    :WriterThreadPool => 20,
    :WriterThreadSpawn => 20,
    :Revactor => 50,
    :ThreadSpawn => 30,
    :ThreadPool => 20,
    :Rev => 50,
    :RevThreadSpawn => 50,
    :RevThreadPool => 50,
    :RevFiberSpawn => 50,
    :Coolio => 50,
    :CoolioThreadSpawn => 50,
    :CoolioThreadPool => 50,
    :CoolioFiberSpawn => 50,
    :EventMachine => 50,
    :FiberSpawn => 50,
    :FiberPool => 50,
    :ActorSpawn => 50,
    :NeverBlock => 50,
  }.each do |model, _|
    u = model.to_s.gsub(/([a-z0-9])([A-Z0-9])/) { "#{$1}_#{$2.downcase!}" }
    autoload model, "rainbows/#{u.downcase!}"
  end
  # :startdoc:
  autoload :Fiber, 'rainbows/fiber' # core class
  autoload :StreamFile, 'rainbows/stream_file'
  autoload :HttpResponse, 'rainbows/http_response' # deprecated
  autoload :ThreadTimeout, 'rainbows/thread_timeout'
  autoload :WorkerYield, 'rainbows/worker_yield'
  autoload :SyncClose, 'rainbows/sync_close'
end

require 'rainbows/error'
require 'rainbows/configurator'
