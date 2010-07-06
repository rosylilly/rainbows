# -*- encoding: binary -*-
require 'rainbows/ev_core'
module Rainbows
  module Rev

    class Client < ::Rev::IO
      include Rainbows::EvCore
      include Rainbows::HttpResponse
      G = Rainbows::G
      HH = Rack::Utils::HeaderHash

      def initialize(io)
        CONN[self] = false
        super(io)
        post_init
        @deferred_bodies = [] # for (fast) regular files only
      end

      def quit
        super
        close if @deferred_bodies.empty? && @_write_buffer.empty?
      end

      # override the ::Rev::IO#write method try to write directly to the
      # kernel socket buffers to avoid an extra userspace copy if
      # possible.
      def write(buf)
        if @_write_buffer.empty?
          begin
            w = @_io.write_nonblock(buf)
            if w == Rack::Utils.bytesize(buf)
              on_write_complete
              return w
            end
            # we never care for the return value, but yes, we may return
            # a "fake" short write from super(buf) if anybody cares.
            buf = buf[w..-1]
          rescue Errno::EAGAIN
            # fall through to super(buf)
          rescue
            close
            return
          end
        end
        super(buf)
      end

      # queued, optional response bodies, it should only be unpollable "fast"
      # devices where read(2) is uninterruptable.  Unfortunately, NFS and ilk
      # are also part of this.  We'll also stick DeferredResponse bodies in
      # here to prevent connections from being closed on us.
      def defer_body(io, out_headers)
        @deferred_bodies << io
        schedule_write unless out_headers # triggers a write
      end

      def timeout?
        @_write_buffer.empty? && @deferred_bodies.empty? and close.nil?
      end

      def rev_write_response(response, out)
        status, headers, body = response

        body.respond_to?(:to_path) or
          return write_response(self, response, out)

        headers = HH.new(headers)
        io = body_to_io(body)
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
          io = DeferredResponse.new(io, self, do_chunk, body).
                                    attach(Server::LOOP)
        elsif st.file?
          headers.delete('Transfer-Encoding')
          headers['Content-Length'] ||= st.size.to_s
          io = to_sendfile(io)
        else # char/block device, directory, whatever... nobody cares
          return write_response(self, response, out)
        end
        defer_body(io, out)
        write_header(self, response, out)
      end

      def app_call
        begin
          KATO.delete(self)
          @env[RACK_INPUT] = @input
          @env[REMOTE_ADDR] = @remote_addr
          response = APP.call(@env.update(RACK_DEFAULTS))
          alive = @hp.keepalive? && G.alive
          out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if @hp.headers?

          rev_write_response(response, out)
          if alive
            @env.clear
            @hp.reset
            @state = :headers
            # keepalive requests are always body-less, so @input is unchanged
            @hp.headers(@env, @buf) and next
            KATO[self] = Time.now
          else
            quit
          end
          return
        end while true
      end

      def on_write_complete
        if body = @deferred_bodies[0]
          # no socket or pipes, body must be a regular file to continue here
          return if DeferredResponse === body

          begin
            begin
              rev_sendfile(body)
            rescue EOFError # expected at file EOF
              @deferred_bodies.shift
              body.close
              close if :close == @state && @deferred_bodies.empty?
            end
          rescue => e
            handle_error(e)
          end
        else
          close if :close == @state
        end
      end

      def on_close
        CONN.delete(self)
      end

    end # module Client
  end # module Rev
end # module Rainbows
