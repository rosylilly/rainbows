# -*- encoding: binary -*-
# :enddoc:
module Rainbows::EventMachine::Response
  def write_response(status, headers, body, alive)
    if body.respond_to?(:errback) && body.respond_to?(:callback)
      @body = body
      body.callback { quit }
      body.errback { quit }
      alive = true
    elsif body.respond_to?(:to_path)
      st = File.stat(path = body.to_path)

      if st.file?
        write_headers(status, headers, alive)
        @body = stream_file_data(path)
        @body.errback do
          body.close if body.respond_to?(:close)
          quit
        end
        @body.callback do
          body.close if body.respond_to?(:close)
          @body = nil
          alive ? receive_data(nil) : quit
        end
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
    quit unless alive
  end
end
