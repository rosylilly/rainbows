# -*- encoding: binary -*-
begin
  require 'fiber'
rescue LoadError
  defined?(NeverBlock) or raise
end

module Rainbows

  # core module for all things that use Fibers in Rainbows!
  module Fiber
    autoload :Base, 'rainbows/fiber/base'
    autoload :Queue, 'rainbows/fiber/queue'
  end
end
