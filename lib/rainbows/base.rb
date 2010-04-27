# -*- encoding: binary -*-

module Rainbows

  # base class for Rainbows concurrency models, this is currently
  # used by ThreadSpawn and ThreadPool models
  module Base

    include Unicorn
    include Rainbows::Const
    G = Rainbows::G

    def init_worker_process(worker)
      super(worker)
      G.tmp = worker.tmp

      # avoid spurious wakeups and blocking-accept() with 1.8 green threads
      if RUBY_VERSION.to_f < 1.9
        require "io/nonblock"
        HttpServer::LISTENERS.each { |l| l.nonblock = true }
      end

      # we're don't use the self-pipe mechanism in the Rainbows! worker
      # since we don't defer reopening logs
      HttpServer::SELF_PIPE.each { |x| x.close }.clear
      trap(:USR1) { reopen_worker_logs(worker.nr) }
      trap(:QUIT) { G.quit! }
      [:TERM, :INT].each { |sig| trap(sig) { exit!(0) } } # instant shutdown
      logger.info "Rainbows! #@use worker_connections=#@worker_connections"
    end

    if IO.respond_to?(:copy_stream)
      def write_body(client, body)
        if body.respond_to?(:to_path)
          io = body.respond_to?(:to_io) ? body.to_io : body.to_path
          IO.copy_stream(io, client)
        else
          body.each { |chunk| client.write(chunk) }
        end
        ensure
          body.respond_to?(:close) and body.close
      end
    else
      def write_body(client, body)
        body.each { |chunk| client.write(chunk) }
        ensure
          body.respond_to?(:close) and body.close
      end
    end

    # once a client is accepted, it is processed in its entirety here
    # in 3 easy steps: read request, call app, write app response
    # this is used by synchronous concurrency models
    #   Base, ThreadSpawn, ThreadPool
    def process_client(client)
      buf = client.readpartial(CHUNK_SIZE) # accept filters protect us here
      hp = HttpParser.new
      env = {}
      alive = true
      remote_addr = Rainbows.addr(client)

      begin # loop
        while ! hp.headers(env, buf)
          IO.select([client], nil, nil, G.kato) or return
          buf << client.readpartial(CHUNK_SIZE)
        end

        env[CLIENT_IO] = client
        env[RACK_INPUT] = 0 == hp.content_length ?
                 HttpRequest::NULL_IO :
                 Unicorn::TeeInput.new(client, env, hp, buf)
        env[REMOTE_ADDR] = remote_addr
        status, headers, body = app.call(env.update(RACK_DEFAULTS))

        if 100 == status.to_i
          client.write(EXPECT_100_RESPONSE)
          env.delete(HTTP_EXPECT)
          status, headers, body = app.call(env)
        end

        alive = hp.keepalive? && G.alive
        if hp.headers?
          out = [ alive ? CONN_ALIVE : CONN_CLOSE ]
          client.write(HttpResponse.header_string(status, headers, out))
        end
        write_body(client, body)
      end while alive and hp.reset.nil? and env.clear
    # if we get any error, try to write something back to the client
    # assuming we haven't closed the socket, but don't get hung up
    # if the socket is already closed or broken.  We'll always ensure
    # the socket is closed at the end of this function
    rescue => e
      Error.write(client, e)
    ensure
      client.close unless client.closed?
    end

    def self.included(klass)
      klass.const_set :LISTENERS, HttpServer::LISTENERS
      klass.const_set :G, Rainbows::G
    end

  end
end
