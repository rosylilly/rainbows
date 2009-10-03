# -*- encoding: binary -*-
require 'rainbows'
module Rainbows

  class HttpServer < ::Unicorn::HttpServer
    include Rainbows

    attr_accessor :worker_connections
    attr_reader :use

    def initialize(app, options)
      self.app = app
      self.reexec_pid = 0
      self.init_listeners = options[:listeners] ? options[:listeners].dup : []
      self.config = Configurator.new(options.merge(:use_defaults => true))
      self.listener_opts = {}
      config.commit!(self, :skip => [:listeners, :pid])

      defined?(@use) or
        self.use = Rainbows.const_get(:ThreadPool)
      defined?(@worker_connections) or
        @worker_connections = 4

      #self.orig_app = app
    end

    def use=(model)
      extend(@use = model)
    end

  end

end
