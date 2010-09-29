# -*- encoding: binary -*-

# base class for \Rainbows! concurrency models, this is currently used by
# ThreadSpawn and ThreadPool models.  Base is also its own
# (non-)concurrency model which is basically Unicorn-with-keepalive, and
# not intended for production use, as keepalive with a pure prefork
# concurrency model is extremely expensive.
module Rainbows::Base

  # :stopdoc:
  include Rainbows::Const
  include Rainbows::Response

  # shortcuts...
  G = Rainbows::G
  NULL_IO = Unicorn::HttpRequest::NULL_IO
  TeeInput = Rainbows::TeeInput
  HttpParser = Unicorn::HttpParser

  # this method is called by all current concurrency models
  def init_worker_process(worker) # :nodoc:
    super(worker)
    Rainbows::Response.setup(self.class)
    Rainbows::MaxBody.setup
    G.tmp = worker.tmp

    listeners = Rainbows::HttpServer::LISTENERS
    Rainbows::HttpServer::IO_PURGATORY.concat(listeners)

    # no need for this when Unicorn uses Kgio
    listeners.map! do |io|
      case io
      when TCPServer
        Kgio::TCPServer.for_fd(io.fileno)
      when UNIXServer
        Kgio::UNIXServer.for_fd(io.fileno)
      else
        io
      end
    end

    # we're don't use the self-pipe mechanism in the Rainbows! worker
    # since we don't defer reopening logs
    Rainbows::HttpServer::SELF_PIPE.each { |x| x.close }.clear
    trap(:USR1) { reopen_worker_logs(worker.nr) }
    trap(:QUIT) { G.quit! }
    [:TERM, :INT].each { |sig| trap(sig) { exit!(0) } } # instant shutdown
    logger.info "Rainbows! #@use worker_connections=#@worker_connections"
  end

  def wait_headers_readable(client)  # :nodoc:
    IO.select([client], nil, nil, G.kato)
  end

  # once a client is accepted, it is processed in its entirety here
  # in 3 easy steps: read request, call app, write app response
  # this is used by synchronous concurrency models
  #   Base, ThreadSpawn, ThreadPool
  def process_client(client) # :nodoc:
    buf = client.readpartial(CHUNK_SIZE) # accept filters protect us here
    hp = HttpParser.new
    env = {}
    remote_addr = Rainbows.addr(client)

    begin # loop
      until hp.headers(env, buf)
        wait_headers_readable(client) or return
        buf << client.readpartial(CHUNK_SIZE)
      end

      env[CLIENT_IO] = client
      env[RACK_INPUT] = 0 == hp.content_length ?
                        NULL_IO : TeeInput.new(client, env, hp, buf)
      env[REMOTE_ADDR] = remote_addr
      status, headers, body = app.call(env.update(RACK_DEFAULTS))

      if 100 == status.to_i
        client.write(EXPECT_100_RESPONSE)
        env.delete(HTTP_EXPECT)
        status, headers, body = app.call(env)
      end

      if hp.headers?
        headers = HH.new(headers)
        range = make_range!(env, status, headers) and status = range.shift
        env = false unless hp.keepalive? && G.alive
        headers[CONNECTION] = env ? KEEP_ALIVE : CLOSE
        client.write(response_header(status, headers))
      end
      write_body(client, body, range)
    end while env && env.clear && hp.reset.nil?
  # if we get any error, try to write something back to the client
  # assuming we haven't closed the socket, but don't get hung up
  # if the socket is already closed or broken.  We'll always ensure
  # the socket is closed at the end of this function
  rescue => e
    Rainbows::Error.write(client, e)
  ensure
    client.close unless client.closed?
  end

  def self.included(klass) # :nodoc:
    klass.const_set :LISTENERS, Rainbows::HttpServer::LISTENERS
    klass.const_set :G, Rainbows::G
  end

  # :startdoc:
end
