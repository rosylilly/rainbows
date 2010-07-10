# -*- encoding: binary -*-
# :enddoc:
# deprecated, use Rainbows::Response instead
# Cramp 0.11 relies on this, and is only activated by Cramp
if defined?(Cramp) && defined?(Rainbows::EventMachine::Client)
  class Rainbows::HttpResponse
    class << self
      include Rainbows::Response
      alias write write_response
    end
  end

  module Rainbows::EventMachine::CrampSocket
    def write_header(_, response, out)
      if websocket?
        write web_socket_upgrade_data
        web_socket_handshake!
        out = nil # disable response headers
      end
      super(self, response, out)
    end
  end

  class Rainbows::EventMachine::Client
    include Rainbows::EventMachine::CrampSocket
  end
end
