# -*- encoding: binary -*-
# :enddoc:
require 'rainbows/coolio_support'
require 'rainbows/fiber'
require 'rainbows/fiber/io'

module Rainbows::Fiber::Rev
  autoload :Heartbeat, 'rainbows/fiber/rev/heartbeat'
  autoload :Server, 'rainbows/fiber/rev/server'
  autoload :Sleeper, 'rainbows/fiber/rev/sleeper'
end
require 'rainbows/fiber/rev/methods'
