# -*- encoding: binary -*-
# :enddoc:
class Rainbows::EventMachine::Client < EM::Connection
  attr_writer :body
  include Rainbows::EvCore

  def initialize(io)
    @_io = io
    @body = nil
  end

  alias write send_data

  def receive_data(data)
    # To avoid clobbering the current streaming response
    # (often a static file), we do not attempt to process another
    # request on the same connection until the first is complete
    if @body
      @buf << data
      @_io.shutdown(Socket::SHUT_RD) if @buf.size > 0x1c000
      EM.next_tick { receive_data('') }
    else
      on_read(data)
    end
  end

  def quit
    super
    close_connection_after_writing
  end

  def app_call
    set_comm_inactivity_timeout 0
    @env[RACK_INPUT] = @input
    @env[REMOTE_ADDR] = @_io.kgio_addr
    @env[ASYNC_CALLBACK] = method(:em_write_response)
    @env[ASYNC_CLOSE] = EM::DefaultDeferrable.new

    response = catch(:async) { APP.call(@env.update(RACK_DEFAULTS)) }

    # too tricky to support pipelining with :async since the
    # second (pipelined) request could be a stuck behind a
    # long-running async response
    (response.nil? || -1 == response[0]) and return @state = :close

    alive = @hp.next? && G.alive && G.kato > 0
    em_write_response(response, alive)
    if alive
      @state = :headers
      if @buf.empty?
        set_comm_inactivity_timeout(G.kato)
      else
        EM.next_tick { receive_data('') }
      end
    end
  end

  def em_write_response(response, alive = false)
    status, headers, body = response
    if @hp.headers?
      headers = HH.new(headers)
      headers[CONNECTION] = alive ? KEEP_ALIVE : CLOSE
    else
      headers = nil
    end

    if body.respond_to?(:errback) && body.respond_to?(:callback)
      @body = body
      body.callback { quit }
      body.errback { quit }
      # async response, this could be a trickle as is in comet-style apps
      headers[CONNECTION] = CLOSE if headers
      alive = true
    elsif body.respond_to?(:to_path)
      st = File.stat(path = body.to_path)

      if st.file?
        write(response_header(status, headers)) if headers
        @body = stream_file_data(path)
        @body.errback do
          body.close if body.respond_to?(:close)
          quit
        end
        @body.callback do
          body.close if body.respond_to?(:close)
          @body = nil
          alive ? receive_data('') : quit
        end
        return
      elsif st.socket? || st.pipe?
        @body = io = body_to_io(body)
        chunk = stream_response_headers(status, headers) if headers
        m = chunk ? Rainbows::EventMachine::ResponseChunkPipe :
                    Rainbows::EventMachine::ResponsePipe
        return EM.watch(io, m, self, alive, body).notify_readable = true
      end
      # char or block device... WTF? fall through to body.each
    end

    write(response_header(status, headers)) if headers
    write_body_each(self, body)
    quit unless alive
  end

  def unbind
    async_close = @env[ASYNC_CLOSE] and async_close.succeed
    @body.respond_to?(:fail) and @body.fail
    begin
      @_io.close
    rescue Errno::EBADF
      # EventMachine's EventableDescriptor::Close() may close
      # the underlying file descriptor without invalidating the
      # associated IO object on errors, so @_io.closed? isn't
      # sufficient.
    end
  end
end
