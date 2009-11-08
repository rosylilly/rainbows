# -*- encoding: binary -*-
require 'rainbows/ev_core'
module Rainbows
  module Rev

    class Client < ::Rev::IO
      include Rainbows::EvCore
      G = Rainbows::G

      def initialize(io)
        G.cur += 1
        super(io)
        post_init
        @deferred_bodies = [] # for (fast) regular files only
      end

      # queued, optional response bodies, it should only be unpollable "fast"
      # devices where read(2) is uninterruptable.  Unfortunately, NFS and ilk
      # are also part of this.  We'll also stick DeferredResponse bodies in
      # here to prevent connections from being closed on us.
      def defer_body(io, out_headers)
        @deferred_bodies << io
        on_write_complete unless out_headers # triggers a write
      end

      def app_call
        begin
          (@env[RACK_INPUT] = @input).rewind
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
          else
            quit
          end
          return
        end while true
      end

      def on_write_complete
        if body = @deferred_bodies.first
          return if DeferredResponse === body
          begin
            begin
              write(body.sysread(CHUNK_SIZE))
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
        G.cur -= 1
      end

    end # module Client
  end # module Rev
end # module Rainbows