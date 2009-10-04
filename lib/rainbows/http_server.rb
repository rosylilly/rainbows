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
      @worker_connections = 1
      rv = super(app, options)
      defined?(@use) or use(:Base)
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
      @use = model
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
