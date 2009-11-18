# -*- encoding: binary -*-
require 'rainbows'
module Rainbows

  class HttpServer < ::Unicorn::HttpServer
    include Rainbows

    class << self
      def setup(block)
        G.server.instance_eval(&block)
      end
    end

    def initialize(app, options)
      G.server = self
      rv = super(app, options)
      defined?(@use) or use(:Base)
      @worker_connections ||= MODEL_WORKER_CONNECTIONS[@use]
    end

    def reopen_worker_logs(worker_nr)
      logger.info "worker=#{worker_nr} reopening logs..."
      Unicorn::Util.reopen_logs
      logger.info "worker=#{worker_nr} done reopening logs"
      rescue
        G.quit! # let the master reopen and refork us
    end

    #:stopdoc:
    #
    # Add one second to the timeout since our fchmod heartbeat is less
    # precise (and must be more conservative) than Unicorn does.  We
    # handle many clients per process and can't chmod on every
    # connection we accept without wasting cycles.  That added to the
    # fact that we let clients keep idle connections open for long
    # periods of time means we have to chmod at a fixed interval.
    alias_method :set_timeout, :timeout=
    undef_method :timeout=
    def timeout=(nr)
      set_timeout(nr + 1)
    end
    #:startdoc:

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
      Const::RACK_DEFAULTS['rainbows.model'] = @use = model.to_sym
      Const::RACK_DEFAULTS['rack.multithread'] = !!(/Thread/ =~ model.to_s)
      case @use
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

    def keepalive_timeout(nr)
      (Integer === nr && nr >= 0) or
        raise ArgumentError, "keepalive must be a non-negative Integer"
      G.kato = nr
    end
  end

end
