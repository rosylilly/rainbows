# -*- encoding: binary -*-
# :enddoc:

# this class is used for most synchronous concurrency models
class Rainbows::Client < Kgio::Socket
  include Rainbows::ProcessClient

  alias write kgio_write
end
