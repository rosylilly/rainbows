# -*- encoding: binary -*-
module Rainbows
  module Rev

    # this is class is specific to Rev for writing large static files
    # or proxying IO-derived objects
    class DeferredResponse < ::Rev::IO
      include Rainbows::Const
      def initialize(io, client, do_chunk, body)
        super(io)
        @client, @do_chunk, @body = client, do_chunk, body
      end

      def on_read(data)
        @do_chunk and @client.write(sprintf("%x\r\n", data.size))
        @client.write(data)
        @do_chunk and @client.write("\r\n")
      end

      def on_close
        @do_chunk and @client.write("0\r\n\r\n")
        @client.quit
        @body.respond_to?(:close) and @body.close
      end
    end # class DeferredResponse
  end # module Rev
end # module Rainbows
