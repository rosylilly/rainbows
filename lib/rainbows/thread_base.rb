# -*- encoding: binary -*-

module Rainbows

  module ThreadBase

    include Unicorn
    include Rainbows::Const

    # write a response without caring if it went out or not
    # This is in the case of untrappable errors
    def emergency_response(client, response_str)
      client.write_nonblock(response_str) rescue nil
      client.close rescue nil
    end

    # once a client is accepted, it is processed in its entirety here
    # in 3 easy steps: read request, call app, write app response
    def process_client(client)
      buf = client.readpartial(CHUNK_SIZE)
      hp = HttpParser.new
      env = {}
      remote_addr = TCPSocket === client ? client.peeraddr.last : LOCALHOST

      begin
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

        out = [ hp.keepalive? ? CONN_ALIVE : CONN_CLOSE ] if hp.headers?
        HttpResponse.write(client, response, out)
      end while hp.keepalive? and hp.reset.nil? and env.clear
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
  end
end

