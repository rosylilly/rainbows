# -*- encoding: binary -*-
module Rainbows
  module Rev

    # this is class is specific to Rev for writing large static files
    # or proxying IO-derived objects
    class DeferredResponse < ::Rev::IO
      include Unicorn
      include Rainbows::Const
      G = Rainbows::G
      HH = Rack::Utils::HeaderHash

      def self.defer!(client, response, out)
        body = response.last
        headers = HH.new(response[1])

        # to_io is not part of the Rack spec, but make an exception
        # here since we can't get here without checking to_path first
        io = body.to_io if body.respond_to?(:to_io)
        io ||= ::IO.new($1.to_i) if body.to_path =~ %r{\A/dev/fd/(\d+)\z}
        io ||= File.open(body.to_path, 'rb')
        st = io.stat

        if st.socket? || st.pipe?
          do_chunk = !!(headers['Transfer-Encoding'] =~ %r{\Achunked\z}i)
          do_chunk = false if headers.delete('X-Rainbows-Autochunk') == 'no'
          # too tricky to support keepalive/pipelining when a response can
          # take an indeterminate amount of time here.
          if out.nil?
            do_chunk = false
          else
            out[0] = CONN_CLOSE
          end

          # we only want to attach to the Rev::Loop belonging to the
          # main thread in Ruby 1.9
          io = new(io, client, do_chunk, body).attach(Server::LOOP)
        elsif st.file?
          headers.delete('Transfer-Encoding')
          headers['Content-Length'] ||= st.size.to_s
        else # char/block device, directory, whatever... nobody cares
          return response
        end
        client.defer_body(io, out)
        [ response.first, headers.to_hash, [] ]
      end

      def self.write(client, response, out)
        response.last.respond_to?(:to_path) and
          response = defer!(client, response, out)
        HttpResponse.write(client, response, out)
      end

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
