# -*- encoding: binary -*-
require 'revactor'

# workaround revactor 0.1.4 still using the old Rev::Buffer
# ref: http://rubyforge.org/pipermail/revactor-talk/2009-October/000034.html
defined?(Rev::Buffer) or Rev::Buffer = IO::Buffer

module Rainbows

  # Enables use of the Actor model through
  # {Revactor}[http://revactor.org] under Ruby 1.9.  It spawns one
  # long-lived Actor for every listen socket in the process and spawns a
  # new Actor for every client connection accept()-ed.
  # +worker_connections+ will limit the number of client Actors we have
  # running at any one time.
  #
  # Applications using this model are required to be reentrant, but
  # generally do not have to worry about race conditions.  Multiple
  # instances of the same app may run in the same address space
  # sequentially (but at interleaved points).  Any network dependencies
  # in the application using this model should be implemented using the
  # \Revactor library as well.

  module Revactor
    require 'rainbows/revactor/tee_input'

    include Base

    # once a client is accepted, it is processed in its entirety here
    # in 3 easy steps: read request, call app, write app response
    def process_client(client)
      buf = client.read or return # this probably does not happen...
      hp = HttpParser.new
      env = {}
      remote_addr = ::Revactor::TCP::Socket === client ?
                    client.remote_addr : LOCALHOST

      begin
        while ! hp.headers(env, buf)
          buf << client.read
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

        out = [ hp.keepalive? ? CONN_ALIVE : CONN_CLOSE ] if hp.headers?
        HttpResponse.write(client, response, out)
      end while hp.keepalive? and hp.reset.nil? and env.clear
      client.close
    # if we get any error, try to write something back to the client
    # assuming we haven't closed the socket, but don't get hung up
    # if the socket is already closed or broken.  We'll always ensure
    # the socket is closed at the end of this function
    rescue EOFError,Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
      emergency_response(client, Const::ERROR_500_RESPONSE)
    rescue HttpParserError # try to tell the client they're bad
      buf.empty? or emergency_response(client, Const::ERROR_400_RESPONSE)
    rescue Object => e
      emergency_response(client, Const::ERROR_500_RESPONSE)
      logger.error "Read error: #{e.inspect}"
      logger.error e.backtrace.join("\n")
    end

    # runs inside each forked worker, this sits around and waits
    # for connections and doesn't die until the parent dies (or is
    # given a INT, QUIT, or TERM signal)
    def worker_loop(worker)
      ppid = master_pid
      init_worker_process(worker)
      alive = worker.tmp # tmp is our lifeline to the master process

      trap(:USR1) { reopen_worker_logs(worker.nr) }
      trap(:QUIT) { alive = false; LISTENERS.each { |s| s.close rescue nil } }
      [:TERM, :INT].each { |sig| trap(sig) { exit!(0) } } # instant shutdown

      root = Actor.current
      root.trap_exit = true

      limit = worker_connections
      listeners = revactorize_listeners
      logger.info "worker=#{worker.nr} ready with Revactor"
      clients = 0

      listeners.map! do |s|
        Actor.spawn(s) do |l|
          begin
            while clients >= limit
              logger.info "busy: clients=#{clients} >= limit=#{limit}"
              Actor.receive { |filter| filter.when(:resume) {} }
            end
            actor = Actor.spawn(l.accept) { |c| process_client(c) }
            clients += 1
            root.link(actor)
          rescue Errno::EAGAIN, Errno::ECONNABORTED
          rescue Object => e
            if alive
              logger.error "Unhandled listen loop exception #{e.inspect}."
              logger.error e.backtrace.join("\n")
            end
          end while alive
        end
      end

      nr = 0
      begin
        Actor.receive do |filter|
          filter.after(1) do
            if alive
              alive.chmod(nr = 0 == nr ? 1 : 0)
              listeners.each { |l| alive = false if l.dead? }
              ppid == Process.ppid or alive = false
            end
          end
          filter.when(Case[:exit, Actor, Object]) do |_,actor,_|
            orig = clients
            clients -= 1
            orig >= limit and listeners.each { |l| l << :resume }
          end
        end
      end while alive || clients > 0
    end

  private

    # write a response without caring if it went out or not
    # This is in the case of untrappable errors
    def emergency_response(client, response_str)
      client.instance_eval do
        # this is Revactor implementation dependent
        @_io.write_nonblock(response_str) rescue nil
      end
      client.close rescue nil
    end

    def revactorize_listeners
      LISTENERS.map do |s|
        if TCPServer === s
          ::Revactor::TCP.listen(s, nil)
        elsif defined?(::Revactor::UNIX) && UNIXServer === s
          ::Revactor::UNIX.listen(s)
        else
          logger.error "your version of Revactor can't handle #{s.inspect}"
          nil
        end
      end.compact
    end

  end
end
