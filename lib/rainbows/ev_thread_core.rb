# -*- encoding: binary -*-
require 'thread' # for Queue
require 'rainbows/ev_core'

module Rainbows

  # base module for mixed Thread + evented models like RevThreadSpawn
  module EvThreadCore
    include EvCore

    def post_init
      super
      @lock = Mutex.new
      @thread = nil
    end

    # we pass ourselves off as a Socket to Unicorn::TeeInput and this
    # is the only method Unicorn::TeeInput requires from the socket
    def readpartial(length, buf = "")
      length == 0 and return buf.replace("")
      # try bufferred reads first
      @tbuf && @tbuf.size > 0 and return buf.replace(@tbuf.read(length))

      tmp = @state.pop
      diff = tmp.size - length
      if diff > 0
        @tbuf ||= ::IO::Buffer.new
        @tbuf.write(tmp[length, tmp.size])
        tmp = tmp[0, length]
      end
      resume
      buf.replace(tmp)
    end

    def app_spawn(input)
      begin
        @thread.nil? or @thread.join # only one thread per connection
        env = @env.dup
        alive, headers = @hp.keepalive?, @hp.headers?
        @thread = Thread.new(self) do |client|
          begin
            env[REMOTE_ADDR] = @remote_addr
            env[RACK_INPUT] = input || TeeInput.new(client, env, @hp, @buf)
            response = APP.call(env.update(RACK_DEFAULTS))
            if 100 == response.first.to_i
              write(EXPECT_100_RESPONSE)
              env.delete(HTTP_EXPECT)
              response = APP.call(env)
            end

            alive &&= G.alive
            out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if headers
            response_write(response, out)
          rescue => e
            handle_error(e) rescue nil
          end
        end
        if alive # in case we pipeline
          @hp.reset
          redo if @hp.headers(@env.clear, @buf)
        end
      end while false
    end

    def on_read(data)
      case @state
      when :headers
        @hp.headers(@env, @buf << data) or return
        if 0 == @hp.content_length
          app_spawn(HttpRequest::NULL_IO) # common case
        else # nil or len > 0
          @state, @tbuf = Queue.new, nil
          app_spawn(nil)
        end
      when Queue
        pause
        @state << data
      end
      rescue => e
        handle_error(e)
    end

  end
end
