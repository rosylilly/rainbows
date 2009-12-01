# -*- encoding: binary -*-
require 'revactor'
Revactor::VERSION >= '0.1.5' or abort 'revactor 0.1.5 is required'

module Rainbows

  # Enables use of the Actor model through
  # {Revactor}[http://revactor.org] under Ruby 1.9.  It spawns one
  # long-lived Actor for every listen socket in the process and spawns a
  # new Actor for every client connection accept()-ed.
  # +worker_connections+ will limit the number of client Actors we have
  # running at any one time.
  #
  # Applications using this model are required to be reentrant, but do
  # not have to worry about race conditions unless they use threads
  # internally.  \Rainbows! does not spawn threads under this model.
  # Multiple instances of the same app may run in the same address space
  # sequentially (but at interleaved points).  Any network dependencies
  # in the application using this model should be implemented using the
  # \Revactor library as well, to take advantage of the networking
  # concurrency features this model provides.

  module Revactor
    require 'rainbows/revactor/tee_input'

    RD_ARGS = {}

    include Base

    # once a client is accepted, it is processed in its entirety here
    # in 3 easy steps: read request, call app, write app response
    def process_client(client)
      defined?(Fcntl::FD_CLOEXEC) and
        client.instance_eval { @_io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) }
      rd_args = [ nil ]
      remote_addr = if ::Revactor::TCP::Socket === client
        rd_args << RD_ARGS
        client.remote_addr
      else
        LOCALHOST
      end
      buf = client.read(*rd_args)
      hp = HttpParser.new
      env = {}
      alive = true

      begin
        while ! hp.headers(env, buf)
          buf << client.read(*rd_args)
        end

        env[Const::RACK_INPUT] = 0 == hp.content_length ?
                 HttpRequest::NULL_IO :
                 Rainbows::Revactor::TeeInput.new(client, env, hp, buf)
        env[Const::REMOTE_ADDR] = remote_addr
        response = app.call(env.update(RACK_DEFAULTS))

        if 100 == response.first.to_i
          client.write(Const::EXPECT_100_RESPONSE)
          env.delete(Const::HTTP_EXPECT)
          response = app.call(env)
        end

        alive = hp.keepalive? && G.alive
        out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if hp.headers?
        HttpResponse.write(client, response, out)
      end while alive and hp.reset.nil? and env.clear
    rescue ::Revactor::TCP::ReadError
    rescue => e
      handle_error(client, e)
    ensure
      client.close
    end

    # runs inside each forked worker, this sits around and waits
    # for connections and doesn't die until the parent dies (or is
    # given a INT, QUIT, or TERM signal)
    def worker_loop(worker)
      init_worker_process(worker)
      RD_ARGS[:timeout] = G.kato if G.kato > 0
      nr = 0
      limit = worker_connections
      actor_exit = Case[:exit, Actor, Object]

      revactorize_listeners.each do |l, close, accept|
        Actor.spawn(l, close, accept) do |l, close, accept|
          Actor.current.trap_exit = true
          l.controller = l.instance_eval { @receiver = Actor.current }
          begin
            while nr >= limit
              l.disable if l.enabled?
              logger.info "busy: clients=#{nr} >= limit=#{limit}"
              Actor.receive do |f|
                f.when(close) {}
                f.when(actor_exit) { nr -= 1 }
                f.after(0.01) {} # another listener could've gotten an exit
              end
            end

            l.enable unless l.enabled?
            Actor.receive do |f|
              f.when(close) {}
              f.when(actor_exit) { nr -= 1 }
              f.when(accept) do |_, _, s|
                nr += 1
                Actor.spawn_link(s) { |c| process_client(c) }
              end
            end
          rescue => e
            Error.listen_loop(e)
          end while G.alive
          Actor.receive do |f|
            f.when(close) {}
            f.when(actor_exit) { nr -= 1 }
          end while nr > 0
        end
      end

      Actor.sleep 1 while G.tick
      expire = Time.now + timeout * 2.0
      Actor.sleep 1 while nr > 0 && Time.now < expire
      rescue Errno::EMFILE => e
    end

    # if we get any error, try to write something back to the client
    # assuming we haven't closed the socket, but don't get hung up
    # if the socket is already closed or broken.  We'll always ensure
    # the socket is closed at the end of this function
    def handle_error(client, e)
      # this is Revactor implementation dependent
      msg = Error.response(e) and
        client.instance_eval { @_io.write_nonblock(msg) }
      rescue
    end

    def revactorize_listeners
      LISTENERS.map do |s|
        case s
        when TCPServer
          l = ::Revactor::TCP.listen(s, nil)
          [ l, T[:tcp_closed, ::Revactor::TCP::Socket],
            T[:tcp_connection, l, ::Revactor::TCP::Socket] ]
        when UNIXServer
          l = ::Revactor::UNIX.listen(s)
          [ l, T[:unix_closed, ::Revactor::UNIX::Socket ],
            T[:unix_connection, l, ::Revactor::UNIX::Socket] ]
        end
      end
    end

  end
end
