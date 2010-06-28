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
    RD_ARGS = {}

    include Base

    # once a client is accepted, it is processed in its entirety here
    # in 3 easy steps: read request, call app, write app response
    def process_client(client)
      io = client.instance_variable_get(:@_io)
      io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
      rd_args = [ nil ]
      remote_addr = if ::Revactor::TCP::Socket === client
        rd_args << RD_ARGS
        client.remote_addr
      else
        Unicorn::HttpRequest::LOCALHOST
      end
      buf = client.read(*rd_args)
      hp = HttpParser.new
      env = {}
      alive = true

      begin
        while ! hp.headers(env, buf)
          buf << client.read(*rd_args)
        end

        env[Const::CLIENT_IO] = client
        env[Const::RACK_INPUT] = 0 == hp.content_length ?
                 NULL_IO :
                 TeeInput.new(PartialSocket.new(client), env, hp, buf)
        env[Const::REMOTE_ADDR] = remote_addr
        response = app.call(env.update(RACK_DEFAULTS))

        if 100 == response[0].to_i
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
      Error.write(io, e)
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
            Error.listen_loop(e)
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

    # Revactor Sockets do not implement readpartial, so we emulate just
    # enough to avoid mucking with TeeInput internals.  Fortunately
    # this code is not heavily used so we can usually avoid the overhead
    # of adding a userspace buffer.
    class PartialSocket < Struct.new(:socket, :rbuf)
      def initialize(socket)
        # IO::Buffer is used internally by Rev which Revactor is based on
        # so we'll always have it available
        super(socket, IO::Buffer.new)
      end

      # Revactor socket reads always return an unspecified amount,
      # sometimes too much
      def readpartial(length, dst = "")
        return dst if length == 0
        # always check and return from the userspace buffer first
        rbuf.size > 0 and return dst.replace(rbuf.read(length))

        # read off the socket since there was nothing in rbuf
        tmp = socket.read

        # we didn't read too much, good, just return it straight back
        # to avoid needlessly wasting memory bandwidth
        tmp.size <= length and return dst.replace(tmp)

        # ugh, read returned too much, copy + reread to avoid slicing
        rbuf << tmp[length, tmp.size]
        dst.replace(tmp[0, length])
      end

      # just proxy any remaining methods TeeInput may use
      def close
        socket.close
      end
    end

  end
end
