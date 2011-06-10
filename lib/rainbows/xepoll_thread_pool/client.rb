# -*- encoding: binary -*-
# :enddoc:
# FIXME: lots of duplication from xepolll_thread_spawn/client

module Rainbows::XEpollThreadPool::Client
  Rainbows.config!(self, :keepalive_timeout, :client_header_buffer_size)
  N = Raindrops.new(1)
  ACCEPTORS = Rainbows::HttpServer::LISTENERS.dup
  extend Rainbows::WorkerYield

  def self.included(klass) # included in Rainbows::Client
    max = Rainbows.server.worker_connections
    ACCEPTORS.map! do |sock|
      Thread.new do
        buf = ""
        begin
          if io = sock.kgio_accept(klass)
            N.incr(0, 1)
            io.epoll_once(buf)
          end
          worker_yield while N[0] >= max
        rescue => e
          Rainbows::Error.listen_loop(e)
        end while Rainbows.alive
      end
    end
  end

  def self.app_run(queue)
    while client = queue.pop
      client.run
    end
  end

  QUEUE = Queue.new
  Rainbows::O[:pool_size].times { Thread.new { app_run(QUEUE) } }

  ep = SleepyPenguin::Epoll
  EP = ep.new
  IN = ep::IN | ep::ET | ep::ONESHOT
  KATO = {}
  KATO.compare_by_identity if KATO.respond_to?(:compare_by_identity)
  LOCK = Mutex.new
  Rainbows.at_quit do
    clients = nil
    LOCK.synchronize { clients = KATO.keys; KATO.clear }
    clients.each { |io| io.closed? or io.close }
  end
  @@last_expire = Time.now

  def kato_set
    LOCK.synchronize { KATO[self] = @@last_expire }
    EP.set(self, IN)
  end

  def kato_delete
    LOCK.synchronize { KATO.delete self }
  end

  def self.loop
    buf = ""
    begin
      EP.wait(nil, 1000) { |_, obj| obj.epoll_run(buf) }
      expire
    rescue Errno::EINTR
    rescue => e
      Rainbows::Error.listen_loop(e)
    end while Rainbows.tick || N[0] > 0
    Rainbows::JoinThreads.acceptors(ACCEPTORS)
  end

  def self.expire
    return if ((now = Time.now) - @@last_expire) < 1.0
    if (ot = KEEPALIVE_TIMEOUT) >= 0
      ot = now - ot
      defer = []
      LOCK.synchronize do
        KATO.delete_if { |client, time| time < ot and defer << client }
      end
      defer.each { |io| io.closed? or io.close }
    end
    @@last_expire = now
  end

  def epoll_once(buf)
    @hp = Rainbows::HttpParser.new
    epoll_run(buf)
  end

  def close
    super
    kato_delete
    N.decr(0, 1)
    nil
  end

  def handle_error(e)
    super
    ensure
      closed? or close
  end

  def queue!
    QUEUE << self
    false
  end

  def epoll_run(buf)
    case kgio_tryread(CLIENT_HEADER_BUFFER_SIZE, buf)
    when :wait_readable
      return kato_set
    when String
      kato_delete
      @hp.add_parse(buf) and return queue!
    else
      return close
    end while true
    rescue => e
      handle_error(e)
  end

  def run
    process_pipeline(@hp.env, @hp)
  end

  def pipeline_ready(hp)
    # be fair to other clients, let others run first
    hp.parse and return queue!
    epoll_run("")
    false
  end
end
