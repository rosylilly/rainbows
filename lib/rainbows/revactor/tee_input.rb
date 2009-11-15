# -*- encoding: binary -*-
require 'rainbows/revactor'

module Rainbows
  module Revactor

    # acts like tee(1) on an input input to provide a input-like stream
    # while providing rewindable semantics through a File/StringIO
    # backing store.  On the first pass, the input is only read on demand
    # so your Rack application can use input notification (upload progress
    # and like).  This should fully conform to the Rack::InputWrapper
    # specification on the public API.  This class is intended to be a
    # strict interpretation of Rack::InputWrapper functionality and will
    # not support any deviations from it.
    class TeeInput < ::Unicorn::TeeInput

    private

      # tees off a +length+ chunk of data from the input into the IO
      # backing store as well as returning it.  +dst+ must be specified.
      # returns nil if reading from the input returns nil
      def tee(length, dst)
        unless parser.body_eof?
          if parser.filter_body(dst, buf << socket.read).nil?
            @tmp.write(dst)
            diff = dst.size - length
            if diff > 0
              dst.replace(dst[0,length])
              @tmp.seek(-diff, IO::SEEK_CUR)
            end
            return dst
          end
        end
        finalize_input
        rescue => e
          client_error(e)
      end

      def finalize_input
        while parser.trailers(req, buf).nil?
          # Don't worry about raising ClientShutdown here on EOFError, tee()
          # will catch EOFError when app is processing it, otherwise in
          # initialize we never get any chance to enter the app so the
          # EOFError will just get trapped by Unicorn and not the Rack app
          buf << socket.read
        end
        self.socket = nil
      end

    end
  end
end
