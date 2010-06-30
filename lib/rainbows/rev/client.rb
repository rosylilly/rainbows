# -*- encoding: binary -*-
require 'rainbows/ev_core'
module Rainbows
  module Rev

    class Client < ::Rev::IO
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

      def app_call
        begin
          KATO.delete(self)
          @env[RACK_INPUT] = @input
          @env[REMOTE_ADDR] = @remote_addr
          response = APP.call(@env.update(RACK_DEFAULTS))
          alive = @hp.keepalive? && G.alive
          out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if @hp.headers?

          DeferredResponse.write(self, response, out)
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

      if IO.method_defined?(:sendfile_nonblock)
        def sendfile(body)
          body.pos += @_io.sendfile_nonblock(body, body.pos, 0x10000)
          rescue Errno::EAGAIN
          ensure
            enable_write_watcher
        end
      else
        def sendfile(body)
          write(body.sysread(CHUNK_SIZE))
        end
      end

      def on_write_complete
        if body = @deferred_bodies[0]
          # no socket or pipes, body must be a regular file to continue here
          return if DeferredResponse === body

          begin
            begin
              sendfile(body)
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
