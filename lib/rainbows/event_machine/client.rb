# -*- encoding: binary -*-
# :enddoc:
require 'rainbows/event_machine/response'
class Rainbows::EventMachine::Client < EM::Connection
  attr_writer :body
  include Rainbows::EvCore
  include Rainbows::EventMachine::Response

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
      if data
        @buf << data
        @_io.shutdown(Socket::SHUT_RD) if @buf.size > 0x1c000
      end
      EM.next_tick { receive_data(nil) } unless @buf.empty?
    else
      on_read(data || "") if (@buf.size > 0) || data
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
    @env[ASYNC_CALLBACK] = method(:write_async_response)
    @env[ASYNC_CLOSE] = EM::DefaultDeferrable.new

    status, headers, body = catch(:async) {
      APP.call(@env.merge!(RACK_DEFAULTS))
    }

    # too tricky to support pipelining with :async since the
    # second (pipelined) request could be a stuck behind a
    # long-running async response
    (status.nil? || -1 == status) and return @state = :close

    if @hp.next?
      @state = :headers
      write_response(status, headers, body, true)
      if @buf.empty?
        set_comm_inactivity_timeout(Rainbows.keepalive_timeout)
      elsif @body.nil?
        EM.next_tick { receive_data(nil) }
      end
    else
      write_response(status, headers, body, false)
    end
  end

  def next!
    @body.close if @body.respond_to?(:close)
    @hp.keepalive? ? receive_data(@body = nil) : quit
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
