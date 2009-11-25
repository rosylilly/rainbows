# -*- encoding: binary -*-
require 'fiber'
require 'rainbows/fiber/io'

module Rainbows
  module Fiber
    RD = {}
    WR = {}

    module Base
      include Rainbows::Base

      def process_client(client)
        G.cur += 1
        io = client.to_io
        buf = client.read_timeout or return
        hp = HttpParser.new
        env = {}
        alive = true
        remote_addr = TCPSocket === io ? io.peeraddr.last : LOCALHOST

        begin # loop
          while ! hp.headers(env, buf)
            buf << client.read_timeout or return
          end

          env[RACK_INPUT] = 0 == hp.content_length ?
                    HttpRequest::NULL_IO : TeeInput.new(client, env, hp, buf)
          env[REMOTE_ADDR] = remote_addr
          response = APP.call(env.update(RACK_DEFAULTS))

          if 100 == response.first.to_i
            client.write(EXPECT_100_RESPONSE)
            env.delete(HTTP_EXPECT)
            response = APP.call(env)
          end

          alive = hp.keepalive? && G.alive
          out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if hp.headers?
          HttpResponse.write(client, response, out)
        end while alive and hp.reset.nil? and env.clear
        io.close
      rescue => e
        handle_error(io, e)
      ensure
        G.cur -= 1
        RD.delete(client)
        WR.delete(client)
      end

    end
  end
end
