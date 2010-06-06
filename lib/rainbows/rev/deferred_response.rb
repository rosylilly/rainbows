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

      def self.write(client, response, out)
        status, headers, body = response

        body.respond_to?(:to_path) or
            return HttpResponse.write(client, response, out)

        headers = HH.new(headers)
        io = Rainbows.body_to_io(body)
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
          return HttpResponse.write(client, response, out)
        end
        client.defer_body(io, out)
        out.nil? or
          client.write(HttpResponse.header_string(status, headers.to_hash, out))
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
