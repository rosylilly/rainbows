# -*- encoding: binary -*-
# :enddoc:

require 'rainbows/timed_read'

class Rainbows::Client < Kgio::Socket
  include Rainbows::TimedRead
end
Kgio.accept_class = Rainbows::Client
