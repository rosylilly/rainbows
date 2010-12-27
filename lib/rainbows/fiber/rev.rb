# -*- encoding: binary -*-
# :enddoc:
begin
  require 'coolio'
rescue LoadError
  require 'rev'
end
require 'rev' if defined?(Coolio)
require 'rainbows/fiber'
require 'rainbows/fiber/io'

module Rainbows::Fiber::Rev
  autoload :Heartbeat, 'rainbows/fiber/rev/heartbeat'
  autoload :Server, 'rainbows/fiber/rev/server'
  autoload :Sleeper, 'rainbows/fiber/rev/sleeper'
end
require 'rainbows/fiber/rev/methods'
