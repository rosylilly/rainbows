# -*- encoding: binary -*-
# :enddoc:

require 'rainbows/read_timeout'

class Rainbows::Client < Kgio::Socket
  include Rainbows::ReadTimeout
end
Kgio.accept_class = Rainbows::Client
