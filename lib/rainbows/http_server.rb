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
      defined?(@use) or use(:ThreadPool)
      defined?(@worker_connections) or worker_connections(4)
      rv
    end

    def use(*args)
      return @use if args.empty?
      model = begin
        Rainbows.const_get(args.first)
      rescue NameError
        raise ArgumentError, "concurrency model #{model.inspect} not supported"
      end

      Module === model or
        raise ArgumentError, "concurrency model #{model.inspect} not supported"
      extend(@use = model)
    end

    def worker_connections(*args)
      return @worker_connections if args.empty?
      nr = args.first
      (Integer === nr && nr > 0) || nr.nil? or
        raise ArgumentError, "worker_connections must be an Integer or nil"
      @worker_connections = nr
    end

  end

end
