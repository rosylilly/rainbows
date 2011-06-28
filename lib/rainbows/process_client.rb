# -*- encoding: binary -*-
# :enddoc:
module Rainbows::ProcessClient
  include Rainbows::Response
  include Rainbows::Const

  NULL_IO = Unicorn::HttpRequest::NULL_IO
  RACK_INPUT = Unicorn::HttpRequest::RACK_INPUT
  IC = Unicorn::HttpRequest.input_class
  Rainbows.config!(self, :client_header_buffer_size, :keepalive_timeout)

  def read_expire
    Time.now + KEEPALIVE_TIMEOUT
  end

  # used for reading headers (respecting keepalive_timeout)
  def timed_read(buf)
    expire = nil
    begin
      case rv = kgio_tryread(CLIENT_HEADER_BUFFER_SIZE, buf)
      when :wait_readable
        return if expire && expire < Time.now
        expire ||= read_expire
        kgio_wait_readable(KEEPALIVE_TIMEOUT)
      else
        return rv
      end
    end while true
  end

  def process_loop
    @hp = hp = Rainbows::HttpParser.new
    kgio_read!(CLIENT_HEADER_BUFFER_SIZE, buf = hp.buf) or return

    begin # loop
      until env = hp.parse
        timed_read(buf2 ||= "") or return
        buf << buf2
      end

      set_input(env, hp)
      env[REMOTE_ADDR] = kgio_addr
      status, headers, body = APP.call(env.merge!(RACK_DEFAULTS))

      if 100 == status.to_i
        write(EXPECT_100_RESPONSE)
        env.delete(HTTP_EXPECT)
        status, headers, body = APP.call(env)
      end
      write_response(status, headers, body, alive = @hp.next?)
    end while alive
  # if we get any error, try to write something back to the client
  # assuming we haven't closed the socket, but don't get hung up
  # if the socket is already closed or broken.  We'll always ensure
  # the socket is closed at the end of this function
  rescue => e
    handle_error(e)
  ensure
    close unless closed?
  end

  def handle_error(e)
    Rainbows::Error.write(self, e)
  end

  def set_input(env, hp)
    env[RACK_INPUT] = 0 == hp.content_length ? NULL_IO : IC.new(self, hp)
  end

  def process_pipeline(env, hp)
    begin
      set_input(env, hp)
      env[REMOTE_ADDR] = kgio_addr
      status, headers, body = APP.call(env.merge!(RACK_DEFAULTS))
      if 100 == status.to_i
        write(EXPECT_100_RESPONSE)
        env.delete(HTTP_EXPECT)
        status, headers, body = APP.call(env)
      end
      write_response(status, headers, body, alive = hp.next?)
    end while alive && pipeline_ready(hp)
    alive or close
    rescue => e
      handle_error(e)
  end

  # override this in subclass/module
  def pipeline_ready(hp)
  end
end
