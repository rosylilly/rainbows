# -*- encoding: binary -*-
require 'unicorn'
require 'rainbows/error'
require 'rainbows/configurator'
require 'fcntl'

module Rainbows

  # global vars because class/instance variables are confusing me :<
  # this struct is only accessed inside workers and thus private to each
  # G.cur may not be used in the network concurrency model
  class State < Struct.new(:alive,:m,:cur,:kato,:server,:tmp,:expire)
    def tick
      tmp.chmod(self.m = m == 0 ? 1 : 0)
      exit!(2) if expire && Time.now >= expire
      alive && server.master_pid == Process.ppid or quit!
    end

    def quit!
      self.alive = false
      self.expire ||= Time.now + (server.timeout * 2.0)
      server.class.const_get(:LISTENERS).map! { |s| s.close rescue nil }
      false
    end
  end
  # :stopdoc:
  G = State.new(true, 0, 0, 5)
  O = {}
  # :startdoc:

  require 'rainbows/const'
  require 'rainbows/http_server'
  require 'rainbows/http_response'
  require 'rainbows/base'
  require 'rainbows/tee_input'
  autoload :Sendfile, 'rainbows/sendfile'
  autoload :AppPool, 'rainbows/app_pool'
  autoload :DevFdResponse, 'rainbows/dev_fd_response'
  autoload :MaxBody, 'rainbows/max_body'
  autoload :QueuePool, 'rainbows/queue_pool'

  class << self

    # Sleeps the current application dispatch.  This will pick the
    # optimal method to sleep depending on the concurrency model chosen
    # (which may still suck and block the entire process).  Using this
    # with the basic :Rev or :EventMachine models is not recommended.
    # This should be used within your Rack application.
    def sleep(nr)
      case G.server.use
      when :FiberPool, :FiberSpawn
        Rainbows::Fiber.sleep(nr)
      when :RevFiberSpawn
        Rainbows::Fiber::Rev::Sleeper.new(nr)
      when :Revactor
        Actor.sleep(nr)
      else
        Kernel.sleep(nr)
      end
    end

    # runs the Rainbows! HttpServer with +app+ and +options+ and does
    # not return until the server has exited.
    def run(app, options = {})
      HttpServer.new(app, options).start.join
    end

    # returns nil if accept fails
    def sync_accept(sock)
      rv = sock.accept
      rv.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
      rv
    rescue Errno::EAGAIN, Errno::ECONNABORTED, Errno::EINTR
    end

    # returns nil if accept fails
    def accept(sock)
      rv = sock.accept_nonblock
      rv.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
      rv
    rescue Errno::EAGAIN, Errno::ECONNABORTED
    end

    # returns a string representing the address of the given client +io+
    # For local UNIX domain sockets, this will return a string referred
    # to by the (non-frozen) Unicorn::HttpRequest::LOCALHOST constant.
    def addr(io)
      io.respond_to?(:peeraddr) ?
                        io.peeraddr[-1] : Unicorn::HttpRequest::LOCALHOST
    end

    # the default max body size is 1 megabyte (1024 * 1024 bytes)
    @@max_bytes = 1024 * 1024

    def max_bytes; @@max_bytes; end
    def max_bytes=(nr); @@max_bytes = nr; end
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
    :EventMachine => 50,
    :FiberSpawn => 50,
    :FiberPool => 50,
    :ActorSpawn => 50,
    :NeverBlock => 50,
    :RevFiberSpawn => 50,
  }.each do |model, _|
    u = model.to_s.gsub(/([a-z0-9])([A-Z0-9])/) { "#{$1}_#{$2.downcase!}" }
    autoload model, "rainbows/#{u.downcase!}"
  end
  # :startdoc:
  autoload :Fiber, 'rainbows/fiber' # core class
  autoload :ByteSlice, 'rainbows/byte_slice'
end
