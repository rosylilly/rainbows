# -*- encoding: binary -*-
# :stopdoc:
module Rainbows::PoolSize
  DEFAULTS = {
    :pool_size => 50, # same as the default worker_connections
  }

  def setup
    o = Rainbows::O
    DEFAULTS.each { |k,v| o[k] ||= v }
    Integer === o[:pool_size] && o[:pool_size] > 0 or
      raise ArgumentError, "pool_size must a be an Integer > 0"
  end
end
