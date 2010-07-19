# -*- encoding: binary -*-
# :enddoc:
require 'rainbows/ev_core'
module Rainbows
  module Rev

    class Client < ::Rev::IO
      include Rainbows::ByteSlice
      include Rainbows::EvCore
      G = Rainbows::G

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
              return on_write_complete
            end
            # we never care for the return value, but yes, we may return
            # a "fake" short write from super(buf) if anybody cares.
            buf = byte_slice(buf, w..-1)
          rescue Errno::EAGAIN
            break # fall through to super(buf)
          rescue
            return close
          end while true
        end
        super(buf)
      end

      # queued, optional response bodies, it should only be unpollable "fast"
      # devices where read(2) is uninterruptable.  Unfortunately, NFS and ilk
      # are also part of this.  We'll also stick DeferredResponse bodies in
      # here to prevent connections from being closed on us.
      def defer_body(io)
        @deferred_bodies << io
        schedule_write
      end

      def next
        @deferred_bodies.shift
      end

      def timeout?
        @_write_buffer.empty? && @deferred_bodies.empty? and close.nil?
      end

      # used for streaming sockets and pipes
      def stream_response(status, headers, io, body)
        c = stream_response_headers(status, headers) if headers
        # we only want to attach to the Rev::Loop belonging to the
        # main thread in Ruby 1.9
        io = (c ? DeferredChunkResponse : DeferredResponse).new(io, self, body)
        defer_body(io.attach(Server::LOOP))
      end

      def rev_write_response(response, alive)
        status, headers, body = response
        headers = @hp.headers? ? HH.new(headers) : nil

        headers[CONNECTION] = alive ? KEEP_ALIVE : CLOSE if headers
        if body.respond_to?(:to_path)
          io = body_to_io(body)
          st = io.stat

          if st.file?
            write(response_header(status, headers)) if headers
            return defer_body(to_sendfile(io))
          elsif st.socket? || st.pipe?
            return stream_response(status, headers, io, body)
          end
          # char or block device... WTF? fall through to body.each
        end
        write(response_header(status, headers)) if headers
        write_body_each(self, body)
      end

      def app_call
        begin
          KATO.delete(self)
          @env[RACK_INPUT] = @input
          @env[REMOTE_ADDR] = @remote_addr
          response = APP.call(@env.update(RACK_DEFAULTS))

          rev_write_response(response, alive = @hp.keepalive? && G.alive)
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
            rev_sendfile(body)
          rescue EOFError # expected at file EOF
            @deferred_bodies.shift
            body.close
            close if :close == @state && @deferred_bodies.empty?
          rescue => e
            handle_error(e)
          end
        else
          close if :close == @state
        end
      end

      def on_close
        while f = @deferred_bodies.shift
          DeferredResponse === f or f.close
        end
        CONN.delete(self)
      end

    end # module Client
  end # module Rev
end # module Rainbows
