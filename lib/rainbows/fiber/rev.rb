# -*- encoding: binary -*-
# :enddoc:
require 'rev'
require 'rainbows/fiber'
require 'rainbows/fiber/io'

module Rainbows::Fiber
  module Rev
    G = Rainbows::G

    # keep-alive timeout class
    class Kato < ::Rev::TimerWatcher
      def initialize
        @watch = []
        super(1, true)
      end

      def <<(fiber)
        @watch << fiber
        enable unless enabled?
      end

      def on_timer
        @watch.uniq!
        while f = @watch.shift
          f.resume if f.alive?
        end
        disable
      end
    end

    class Heartbeat < ::Rev::TimerWatcher
      def on_timer
        exit if (! G.tick && G.cur <= 0)
      end
    end

    class Sleeper < ::Rev::TimerWatcher

      def initialize(seconds)
        @f = ::Fiber.current
        super(seconds, false)
        attach(::Rev::Loop.default)
        ::Fiber.yield
      end

      def on_timer
        @f.resume
      end
    end

    class Server < ::Rev::IOWatcher
      include Unicorn
      include Rainbows
      include Rainbows::Const
      include Rainbows::Response
      FIO = Rainbows::Fiber::IO

      def to_io
        @io
      end

      def initialize(io)
        @io = io
        super(self, :r)
      end

      def close
        detach if attached?
        @io.close
      end

      def on_readable
        return if G.cur >= MAX
        c = Rainbows.accept(@io) and ::Fiber.new { process(c) }.resume
      end

      def process(io)
        G.cur += 1
        client = FIO.new(io, ::Fiber.current)
        buf = client.read_timeout or return
        hp = HttpParser.new
        env = {}
        remote_addr = Rainbows.addr(io)

        begin # loop
          buf << (client.read_timeout or return) until hp.headers(env, buf)

          env[CLIENT_IO] = client
          env[RACK_INPUT] = 0 == hp.content_length ?
                    HttpRequest::NULL_IO : TeeInput.new(client, env, hp, buf)
          env[REMOTE_ADDR] = remote_addr
          status, headers, body = APP.call(env.update(RACK_DEFAULTS))

          if 100 == status.to_i
            client.write(EXPECT_100_RESPONSE)
            env.delete(HTTP_EXPECT)
            status, headers, body = APP.call(env)
          end

          if hp.headers?
            headers = HH.new(headers)
            range = parse_range(env, status, headers) and status = range.shift
            headers[CONNECTION] = if hp.keepalive? && G.alive
              KEEP_ALIVE
            else
              env = false
              CLOSE
            end
            client.write(response_header(status, headers))
          end
          write_body(client, body, range)
        end while env && env.clear && hp.reset.nil?
      rescue => e
        Error.write(io, e)
      ensure
        G.cur -= 1
        client.close
      end
    end
  end

  class IO # see rainbows/fiber/io for original definition

    class Watcher < ::Rev::IOWatcher
      def initialize(fio, flag)
        @fiber = fio.f
        super(fio, flag)
        attach(::Rev::Loop.default)
      end

      def on_readable
        @fiber.resume
      end

      alias on_writable on_readable
    end

    undef_method :wait_readable
    undef_method :wait_writable
    undef_method :close

    def initialize(*args)
      super
      @r = @w = false
    end

    def close
      @w.detach if @w
      @r.detach if @r
      @r = @w = false
      to_io.close unless to_io.closed?
    end

    def wait_writable
      @w ||= Watcher.new(self, :w)
      @w.enable unless @w.enabled?
      ::Fiber.yield
      @w.disable
    end

    def wait_readable
      @r ||= Watcher.new(self, :r)
      @r.enable unless @r.enabled?
      KATO << f
      ::Fiber.yield
      @r.disable
    end
  end
end
