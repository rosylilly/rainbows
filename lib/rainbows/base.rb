# -*- encoding: binary -*-

module Rainbows

  # base class for Rainbows concurrency models, this is currently
  # used by ThreadSpawn and ThreadPool models
  module Base

    include Unicorn
    include Rainbows::Const
    G = Rainbows::G

    # write a response without caring if it went out or not for error
    # messages.
    # TODO: merge into Unicorn::HttpServer
    def emergency_response(client, response_str)
      client.write_nonblock(response_str) rescue nil
      client.close rescue nil
    end

    def listen_loop_error(e)
      G.alive or return
      logger.error "Unhandled listen loop exception #{e.inspect}."
      logger.error e.backtrace.join("\n")
    end

    def init_worker_process(worker)
      super(worker)
      G.cur = 0
      G.max = worker_connections
      G.logger = logger
      G.app = app

      # we're don't use the self-pipe mechanism in the Rainbows! worker
      # since we don't defer reopening logs
      HttpServer::SELF_PIPE.each { |x| x.close }.clear
      trap(:USR1) { reopen_worker_logs(worker.nr) rescue nil }
      trap(:QUIT) do
        G.alive = false
        # closing anything we IO.select on will raise EBADF
        HttpServer::LISTENERS.map! { |s| s.close rescue nil }
      end
      [:TERM, :INT].each { |sig| trap(sig) { exit!(0) } } # instant shutdown
      logger.info "Rainbows! #@use worker_connections=#@worker_connections"
    end

    # once a client is accepted, it is processed in its entirety here
    # in 3 easy steps: read request, call app, write app response
    def process_client(client)
      buf = client.readpartial(CHUNK_SIZE)
      hp = HttpParser.new
      env = {}
      alive = true
      remote_addr = TCPSocket === client ? client.peeraddr.last : LOCALHOST

      begin # loop
        while ! hp.headers(env, buf)
          buf << client.readpartial(CHUNK_SIZE)
        end

        env[RACK_INPUT] = 0 == hp.content_length ?
                 HttpRequest::NULL_IO :
                 Unicorn::TeeInput.new(client, env, hp, buf)
        env[REMOTE_ADDR] = remote_addr
        response = app.call(env.update(RACK_DEFAULTS))

        if 100 == response.first.to_i
          client.write(EXPECT_100_RESPONSE)
          env.delete(HTTP_EXPECT)
          response = app.call(env)
        end

        alive = hp.keepalive? && G.alive
        out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if hp.headers?
        HttpResponse.write(client, response, out)
      end while alive and hp.reset.nil? and env.clear
      client.close
    # if we get any error, try to write something back to the client
    # assuming we haven't closed the socket, but don't get hung up
    # if the socket is already closed or broken.  We'll always ensure
    # the socket is closed at the end of this function
    rescue EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
      emergency_response(client, ERROR_500_RESPONSE)
    rescue HttpParserError # try to tell the client they're bad
      buf.empty? or emergency_response(client, ERROR_400_RESPONSE)
    rescue Object => e
      emergency_response(client, ERROR_500_RESPONSE)
      logger.error "Read error: #{e.inspect}"
      logger.error e.backtrace.join("\n")
    end

    def join_threads(threads, worker)
      Rainbows::G.alive = false
      expire = Time.now + (timeout * 2.0)
      m = 0
      until (threads.delete_if { |thr| ! thr.alive? }).empty?
        threads.each { |thr|
          worker.tmp.chmod(m = 0 == m ? 1 : 0)
          thr.join(1)
          break if Time.now >= expire
        }
      end
    end

    def self.included(klass)
      klass.const_set :LISTENERS, HttpServer::LISTENERS
      klass.const_set :G, Rainbows::G
    end

  end
end
