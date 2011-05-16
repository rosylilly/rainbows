# -*- encoding: binary -*-
require 'kgio'
require 'unicorn'
require 'io/wait'
Unicorn::SocketHelper::DEFAULTS.merge!({
  # the value passed to TCP_DEFER_ACCEPT actually matters in Linux 2.6.32+
  :tcp_defer_accept => 60,

  # keep-alive performance sucks without this due to
  # write(headers)-write(body)-read
  # because we always write headers and bodies with two calls
  :tcp_nodelay => true,

  # we always want to send our headers out ASAP since Rainbows!
  # is designed for apps that could trickle out the body slowly
  :tcp_nopush => false,
})

# See http://rainbows.rubyforge.org/ for documentation
module Rainbows
  # :stopdoc:
  O = {}

  # map of numeric file descriptors to IO objects to avoid using IO.new
  # and potentially causing race conditions when using /dev/fd/
  FD_MAP = {}
  FD_MAP.compare_by_identity if FD_MAP.respond_to?(:compare_by_identity)

  require 'rainbows/const'
  require 'rainbows/http_parser'
  require 'rainbows/http_server'
  autoload :Response, 'rainbows/response'
  autoload :ProcessClient, 'rainbows/process_client'
  autoload :Client, 'rainbows/client'
  autoload :Base, 'rainbows/base'
  autoload :Sendfile, 'rainbows/sendfile'
  autoload :AppPool, 'rainbows/app_pool'
  autoload :DevFdResponse, 'rainbows/dev_fd_response'
  autoload :MaxBody, 'rainbows/max_body'
  autoload :QueuePool, 'rainbows/queue_pool'
  autoload :EvCore, 'rainbows/ev_core'
  autoload :SocketProxy, 'rainbows/socket_proxy'

  # :startdoc:
  # Sleeps the current application dispatch.  This will pick the
  # optimal method to sleep depending on the concurrency model chosen
  # (which may still suck and block the entire process).  Using this
  # with the basic :Coolio or :EventMachine models is not recommended.
  # This should be used within your Rack application.
  def self.sleep(seconds)
    case Rainbows.server.use
    when :FiberPool, :FiberSpawn
      Rainbows::Fiber.sleep(seconds)
    when :RevFiberSpawn, :CoolioFiberSpawn
      Rainbows::Fiber::Coolio::Sleeper.new(seconds)
    when :Revactor
      Actor.sleep(seconds)
    else
      Kernel.sleep(seconds)
    end
  end
  # :stopdoc:

  # runs the Rainbows! HttpServer with +app+ and +options+ and does
  # not return until the server has exited.
  def self.run(app, options = {}) # :nodoc:
    HttpServer.new(app, options).start.join
  end

  class << self
    attr_accessor :server
    attr_accessor :cur # may not always be used
    attr_reader :alive
    attr_writer :tick_io
    attr_writer :forked
  end

  def self.config!(mod, *opts)
    @forked or abort "#{mod} should only be loaded in a worker process"
    opts.each do |opt|
      mod.const_set(opt.to_s.upcase, Rainbows.server.__send__(opt))
    end
  end

  @alive = true
  @cur = 0
  @tick_mod = 0
  @expire = nil
  @at_quit = []

  def self.at_quit(&block)
    @at_quit << block
  end

  def self.tick
    @tick_io.chmod(@tick_mod = 0 == @tick_mod ? 1 : 0)
    exit!(2) if @expire && Time.now >= @expire
    @alive && @server.master_pid == Process.ppid or quit!
  end

  def self.cur_alive
    @alive || @cur > 0
  end

  def self.quit!
    unless @expire
      @alive = false
      Rainbows::HttpParser.quit
      @expire = Time.now + (@server.timeout * 2.0)
      Unicorn::HttpServer::LISTENERS.each { |s| s.close rescue nil }.clear
      @at_quit.each { |task| task.call }
    end
    false
  end

  autoload :Base, "rainbows/base"
  autoload :WriterThreadPool, "rainbows/writer_thread_pool"
  autoload :WriterThreadSpawn, "rainbows/writer_thread_spawn"
  autoload :Revactor, "rainbows/revactor"
  autoload :ThreadSpawn, "rainbows/thread_spawn"
  autoload :ThreadPool, "rainbows/thread_pool"
  autoload :Rev, "rainbows/rev"
  autoload :RevThreadSpawn, "rainbows/rev_thread_spawn"
  autoload :RevThreadPool, "rainbows/rev_thread_pool"
  autoload :RevFiberSpawn, "rainbows/rev_fiber_spawn"
  autoload :Coolio, "rainbows/coolio"
  autoload :CoolioThreadSpawn, "rainbows/coolio_thread_spawn"
  autoload :CoolioThreadPool, "rainbows/coolio_thread_pool"
  autoload :CoolioFiberSpawn, "rainbows/coolio_fiber_spawn"
  autoload :Epoll, "rainbows/epoll"
  autoload :XEpoll, "rainbows/xepoll"
  autoload :EventMachine, "rainbows/event_machine"
  autoload :FiberSpawn, "rainbows/fiber_spawn"
  autoload :FiberPool, "rainbows/fiber_pool"
  autoload :ActorSpawn, "rainbows/actor_spawn"
  autoload :NeverBlock, "rainbows/never_block"
  autoload :XEpollThreadSpawn, "rainbows/xepoll_thread_spawn"
  autoload :XEpollThreadPool, "rainbows/xepoll_thread_pool"

  autoload :Fiber, 'rainbows/fiber' # core class
  autoload :StreamFile, 'rainbows/stream_file'
  autoload :HttpResponse, 'rainbows/http_response' # deprecated
  autoload :ThreadTimeout, 'rainbows/thread_timeout'
  autoload :WorkerYield, 'rainbows/worker_yield'
  autoload :SyncClose, 'rainbows/sync_close'
  autoload :ReverseProxy, 'rainbows/reverse_proxy'
  autoload :JoinThreads, 'rainbows/join_threads'
  autoload :PoolSize, 'rainbows/pool_size'
end

require 'rainbows/error'
require 'rainbows/configurator'
