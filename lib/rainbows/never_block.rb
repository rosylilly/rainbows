# -*- encoding: binary -*-

# {NeverBlock}[www.espace.com.eg/neverblock/] library that combines
# the EventMachine library with Ruby Fibers.  This includes use of
# Thread-based Fibers under Ruby 1.8.  It currently does NOT support
# a streaming "rack.input" but is compatible with everything else
# EventMachine supports.
#
# === :pool_size vs worker_connections
#
# In your Rainbows! config block, you may specify a Fiber pool size
# to limit your application concurrency (without using Rainbows::AppPool)
# independently of worker_connections.
#
#   Rainbows! do
#     use :NeverBlock, :pool_size => 50
#     worker_connections 100
#   end
#
module Rainbows::NeverBlock
  # :stopdoc:
  extend Rainbows::PoolSize

  # same pool size NB core itself uses
  def self.setup # :nodoc:
    super
    Rainbows::O[:backend] ||= :EventMachine # no Cool.io support, yet
    Rainbows.const_get(Rainbows::O[:backend])
    require "never_block" # require EM first since we need a higher version
  end

  def self.extended(klass)
    klass.extend(Rainbows.const_get(Rainbows::O[:backend])) # EventMachine
    klass.extend(Rainbows::NeverBlock::Core)
  end
  # :startdoc:
end
# :enddoc:
require 'rainbows/never_block/core'
