# -*- encoding: binary -*-
module Rainbows

  class Configurator < ::Unicorn::Configurator

    # configures rainbows
    def rainbows(&block)
      block_given? or raise ArgumentError, "rainbows requires a block"
      instance_eval(&block)
    end

  private

    def use(model)
      assert_in_rainbows
      begin
        model = Rainbows.const_get(model)
      rescue NameError
        raise ArgumentError, "concurrency model #{model.inspect} not supported"
      end

      Module === model or
        raise ArgumentError, "concurrency model #{model.inspect} not supported"
      set[:use] = model
    end

    def worker_connections(nr)
      assert_in_rainbows
      (Integer === nr && nr > 0) || nr.nil? or
        raise ArgumentError, "worker_connections must be an Integer or nil"
      set[:worker_connections] = nr
    end

  private

    def assert_in_rainbows # :nodoc:
      c = caller
      c.grep(/`rainbows'\z/).empty? and
        raise ArgumentError,
             "#{%r!`(\w+)'\z!.match(c.first)[1]} must be called in `rainbows'"
    end

  end

end
