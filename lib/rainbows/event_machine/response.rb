# -*- encoding: binary -*-
# :enddoc:
module Rainbows::EventMachine::Response
  def deferred_errback(orig_body)
    @body.errback do
      orig_body.close if orig_body.respond_to?(:close)
      quit
    end
  end

  def deferred_callback(orig_body, alive)
    @body.callback do
      orig_body.close if orig_body.respond_to?(:close)
      @body = nil
      alive ? receive_data(nil) : quit
    end
  end

  def write_response(status, headers, body, alive)
    @state = :headers if alive
    if body.respond_to?(:errback) && body.respond_to?(:callback)
      @body = body
      deferred_errback(body)
      deferred_callback(body, alive)
    elsif body.respond_to?(:to_path)
      st = File.stat(path = body.to_path)

      if st.file?
        write_headers(status, headers, alive)
        @body = stream_file_data(path)
        deferred_errback(body)
        deferred_callback(body, alive)
        return
      elsif st.socket? || st.pipe?
        io = body_to_io(@body = body)
        chunk = stream_response_headers(status, headers, alive)
        m = chunk ? Rainbows::EventMachine::ResponseChunkPipe :
                    Rainbows::EventMachine::ResponsePipe
        return EM.watch(io, m, self).notify_readable = true
      end
      # char or block device... WTF? fall through to body.each
    end
    super(status, headers, body, alive)
    if alive
      if @body.nil?
        if @buf.empty?
          set_comm_inactivity_timeout(Rainbows.keepalive_timeout)
        else
          EM.next_tick { receive_data(nil) }
        end
      end
    else
      quit unless @body
    end
  end
end
