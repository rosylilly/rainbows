# -*- encoding: binary -*-
require 'revactor'
require 'fcntl'
Revactor::VERSION >= '0.1.5' or abort 'revactor 0.1.5 is required'

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
module Rainbows::Revactor

  # :stopdoc:
  RD_ARGS = {}

  autoload :Proxy, 'rainbows/revactor/proxy'
  autoload :TeeSocket, 'rainbows/revactor/tee_socket'

  include Rainbows::Base
  LOCALHOST = Kgio::LOCALHOST
  TCP = Revactor::TCP::Socket

  # once a client is accepted, it is processed in its entirety here
  # in 3 easy steps: read request, call app, write app response
  def process_client(client) # :nodoc:
    io = client.instance_variable_get(:@_io)
    io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
    rd_args = [ nil ]
    remote_addr = if TCP === client
      rd_args << RD_ARGS
      client.remote_addr
    else
      LOCALHOST
    end
    hp = Unicorn::HttpParser.new
    buf = hp.buf
    alive = false

    begin
      ts = nil
      until env = hp.parse
        buf << client.read(*rd_args)
      end

      env[CLIENT_IO] = client
      env[RACK_INPUT] = 0 == hp.content_length ?
               NULL_IO : IC.new(ts = TeeSocket.new(client), hp)
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
        alive = hp.next? && G.alive && G.kato > 0
        headers[CONNECTION] = alive ? KEEP_ALIVE : CLOSE
        client.write(response_header(status, headers))
        alive && ts and buf << ts.leftover
      end
      write_body(client, body, range)
    end while alive
  rescue Revactor::TCP::ReadError
  rescue => e
    Rainbows::Error.write(io, e)
  ensure
    client.close
  end

  # runs inside each forked worker, this sits around and waits
  # for connections and doesn't die until the parent dies (or is
  # given a INT, QUIT, or TERM signal)
  def worker_loop(worker) #:nodoc:
    init_worker_process(worker)
    require 'rainbows/revactor/body'
    self.class.__send__(:include, Rainbows::Revactor::Body)
    self.class.const_set(:IC, Unicorn::HttpRequest.input_class)
    RD_ARGS[:timeout] = G.kato if G.kato > 0
    nr = 0
    limit = worker_connections
    actor_exit = Case[:exit, Actor, Object]

    revactorize_listeners.each do |l, close, accept|
      Actor.spawn(l, close, accept) do |l, close, accept|
        Actor.current.trap_exit = true
        l.controller = l.instance_variable_set(:@receiver, Actor.current)
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
          Rainbows::Error.listen_loop(e)
        end while G.alive
        Actor.receive do |f|
          f.when(close) {}
          f.when(actor_exit) { nr -= 1 }
        end while nr > 0
      end
    end

    Actor.sleep 1 while G.tick || nr > 0
    rescue Errno::EMFILE
      # ignore, let another worker process take it
  end

  def revactorize_listeners
    LISTENERS.map do |s|
      case s
      when TCPServer
        l = Revactor::TCP.listen(s, nil)
        [ l, T[:tcp_closed, Revactor::TCP::Socket],
          T[:tcp_connection, l, Revactor::TCP::Socket] ]
      when UNIXServer
        l = Revactor::UNIX.listen(s)
        [ l, T[:unix_closed, Revactor::UNIX::Socket ],
          T[:unix_connection, l, Revactor::UNIX::Socket] ]
      end
    end
  end
  # :startdoc:
end
