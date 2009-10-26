# -*- encoding: binary -*-
require 'rainbows'
module Rainbows

  class HttpServer < ::Unicorn::HttpServer
    include Rainbows

    @@instance = nil

    class << self
      def setup(block)
        @@instance.instance_eval(&block)
      end
    end

    def initialize(app, options)
      @@instance = self
      rv = super(app, options)
      defined?(@use) or use(:Base)
      @worker_connections ||= MODEL_WORKER_CONNECTIONS[@use]
    end

    def use(*args)
      model = args.shift or return @use
      mod = begin
        Rainbows.const_get(model)
      rescue NameError
        raise ArgumentError, "concurrency model #{model.inspect} not supported"
      end

      Module === mod or
        raise ArgumentError, "concurrency model #{model.inspect} not supported"
      extend(mod)
      Const::RACK_DEFAULTS['rainbows.model'] = @use = model
      Const::RACK_DEFAULTS['rack.multithread'] = !!(/Thread/ =~ model.to_s)
      case model
      when :Rev, :EventMachine
        Const::RACK_DEFAULTS['rainbows.autochunk'] = true
      end
    end

    def worker_connections(*args)
      return @worker_connections if args.empty?
      nr = args.first
      (Integer === nr && nr > 0) or
        raise ArgumentError, "worker_connections must be a positive Integer"
      @worker_connections = nr
    end

  end

end
