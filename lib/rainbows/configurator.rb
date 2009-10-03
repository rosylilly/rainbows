require 'rainbows'
module Rainbows

  class Configurator < ::Unicorn::Configurator

    def use(model)
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
      (Integer === nr && nr > 0) || nr.nil? or
        raise ArgumentError, "worker_connections must be an Integer or nil"
    end

  end

end
