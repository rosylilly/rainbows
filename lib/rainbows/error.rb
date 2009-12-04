# -*- encoding: binary -*-
module Rainbows

  class Error
    class << self

      def app(e)
        G.server.logger.error "app error: #{e.inspect}"
        G.server.logger.error e.backtrace.join("\n")
        rescue
      end

      def listen_loop(e)
        G.alive or return
        G.server.logger.error "listen loop error: #{e.inspect}."
        G.server.logger.error e.backtrace.join("\n")
        rescue
      end

      def response(e)
        case e
        when EOFError, Errno::ECONNRESET,Errno::EPIPE,Errno::EINVAL,Errno::EBADF
          # swallow error if client shuts down one end or disconnects
        when Unicorn::HttpParserError
          Const::ERROR_400_RESPONSE # try to tell the client they're bad
        when IOError # HttpParserError is an IOError
        else
          app(e)
          Const::ERROR_500_RESPONSE
        end
      end

    end
  end
end
