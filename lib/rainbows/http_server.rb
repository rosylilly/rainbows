# -*- encoding: binary -*-
# :enddoc:

class Rainbows::HttpServer < Unicorn::HttpServer
  attr_accessor :copy_stream
  attr_accessor :worker_connections
  attr_accessor :keepalive_timeout
  attr_accessor :client_header_buffer_size
  attr_accessor :client_max_body_size
  attr_reader :use

  def self.setup(block)
    Rainbows.server.instance_eval(&block)
  end

  def initialize(app, options)
    Rainbows.server = self
    @logger = Unicorn::Configurator::DEFAULTS[:logger]
    super(app, options)
    defined?(@use) or self.use = Rainbows::Base
    @worker_connections ||= @use == :Base ? 1 : 50
  end

  # Add one second to the timeout since our fchmod heartbeat is less
  # precise (and must be more conservative) than Unicorn does.  We
  # handle many clients per process and can't chmod on every
  # connection we accept without wasting cycles.  That added to the
  # fact that we let clients keep idle connections open for long
  # periods of time means we have to chmod at a fixed interval.
  def timeout=(nr)
    @timeout = nr + 1
  end

  def load_config!
    super
    @worker_connections = 1 if @use == :Base
  end

  def worker_loop(worker)
    Rainbows.forked = true
    orig = method(:worker_loop)
    extend(Rainbows.const_get(@use))
    m = method(:worker_loop)
    orig == m ? super(worker) : worker_loop(worker)
  end

  def spawn_missing_workers
    # 5: std{in,out,err} + heartbeat FD + per-process listener
    nofile = 5 + @worker_connections + LISTENERS.size
    trysetrlimit(:RLIMIT_NOFILE, nofile)

    case @use
    when :ThreadSpawn, :ThreadPool, :ActorSpawn,
         :CoolioThreadSpawn, :RevThreadSpawn,
         :XEpollThreadSpawn, :WriterThreadPool, :WriterThreadSpawn
      trysetrlimit(:RLIMIT_NPROC, @worker_connections + LISTENERS.size + 1)
    when :XEpollThreadPool, :CoolioThreadPool
      trysetrlimit(:RLIMIT_NPROC, Rainbows::O[:pool_size] + LISTENERS.size + 1)
    end
    super
  end

  def trysetrlimit(resource, want)
    var = Process.const_get(resource)
    cur, max = Process.getrlimit(var)
    cur <= want and Process.setrlimit(var, cur = max > want ? max : want)
    if cur == want
      @logger.warn "#{resource} rlim_cur=#{cur} is barely enough"
      @logger.warn "#{svc} may monopolize resources dictated by #{resource}" \
                   " and leave none for your app"
    end
    rescue => e
      @logger.error e.message
      @logger.error "#{resource} needs to be increased to >=#{want} before" \
                    " starting #{svc}"
  end

  def svc
    File.basename($0)
  end

  def use=(mod)
    @use = mod.to_s.split(/::/)[-1].to_sym
    new_defaults = {
      'rainbows.model' => @use,
      'rack.multithread' => !!(mod.to_s =~ /Thread/),
      'rainbows.autochunk' => [:Coolio,:Rev,:Epoll,:XEpoll,
                               :EventMachine,:NeverBlock].include?(@use),
    }
    Rainbows::Const::RACK_DEFAULTS.update(new_defaults)
  end

  def keepalive_requests=(nr)
    Unicorn::HttpRequest.keepalive_requests = nr
  end

  def keepalive_requests
    Unicorn::HttpRequest.keepalive_requests
  end

  def client_max_header_size=(bytes)
    Unicorn::HttpParser.max_header_len = bytes
  end
end
