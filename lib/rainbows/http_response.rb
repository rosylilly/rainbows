# -*- encoding: binary -*-
# deprecated, use Rainbows::Response instead
# Cramp 0.11 relies on this
# :enddoc:
class Rainbows::HttpResponse
  class << self
    include Rainbows::Response
    alias write write_response
  end
end
