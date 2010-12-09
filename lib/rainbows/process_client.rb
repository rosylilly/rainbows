# -*- encoding: binary -*-
# :enddoc:
require 'rainbows/rack_input'
module Rainbows::ProcessClient
  G = Rainbows::G
  include Rainbows::Response
  HttpParser = Unicorn::HttpParser
  include Rainbows::RackInput
  include Rainbows::Const

  # once a client is accepted, it is processed in its entirety here
  # in 3 easy steps: read request, call app, write app response
  # this is used by synchronous concurrency models
  #   Base, ThreadSpawn, ThreadPool
  def process_client(client) # :nodoc:
    hp = HttpParser.new
    client.kgio_read!(16384, buf = hp.buf)
    remote_addr = client.kgio_addr
    alive = false

    begin # loop
      until env = hp.parse
        client.timed_read(buf2 ||= "") or return
        buf << buf2
      end

      set_input(env, hp, client)
      env[REMOTE_ADDR] = remote_addr
      status, headers, body = APP.call(env.update(RACK_DEFAULTS))

      if 100 == status.to_i
        client.write(EXPECT_100_RESPONSE)
        env.delete(HTTP_EXPECT)
        status, headers, body = APP.call(env)
      end

      if hp.headers?
        headers = HH.new(headers)
        range = make_range!(env, status, headers) and status = range.shift
        alive = hp.next? && G.alive
        headers[CONNECTION] = alive ? KEEP_ALIVE : CLOSE
        client.write(response_header(status, headers))
      end
      write_body(client, body, range)
    end while alive
  # if we get any error, try to write something back to the client
  # assuming we haven't closed the socket, but don't get hung up
  # if the socket is already closed or broken.  We'll always ensure
  # the socket is closed at the end of this function
  rescue => e
    Rainbows::Error.write(client, e)
  ensure
    client.close unless client.closed?
  end
end
