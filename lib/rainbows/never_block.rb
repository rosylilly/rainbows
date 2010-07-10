# -*- encoding: binary -*-

module Rainbows

  # {NeverBlock}[www.espace.com.eg/neverblock/] library that combines
  # the EventMachine library with Ruby Fibers.  This includes use of
  # Thread-based Fibers under Ruby 1.8.  It currently does NOT support
  # a streaming "rack.input" but is compatible with everything else
  # EventMachine supports.
  #
  # In your Rainbows! config block, you may specify a Fiber pool size
  # to limit your application concurrency (without using Rainbows::AppPool)
  #
  #   Rainbows! do
  #     use :NeverBlock, :pool_size => 50
  #     worker_connections 100
  #   end
  #
  module NeverBlock

    # :stopdoc:
    DEFAULTS = {
      :pool_size => 20, # same default size used by NB
      :backend => :EventMachine, # NeverBlock doesn't support Rev yet
    }

    # same pool size NB core itself uses
    def self.setup # :nodoc:
      DEFAULTS.each { |k,v| O[k] ||= v }
      Integer === O[:pool_size] && O[:pool_size] > 0 or
        raise ArgumentError, "pool_size must a be an Integer > 0"
      mod = Rainbows.const_get(O[:backend])
      require "never_block" # require EM first since we need a higher version
      G.server.extend(mod)
      G.server.extend(Core)
    end

    module Core  # :nodoc: all
      def self.setup
        self.const_set(:POOL, ::NB::Pool::FiberPool.new(O[:pool_size]))
        base = O[:backend].to_s.gsub!(/([a-z])([A-Z])/, '\1_\2').downcase!
        require "rainbows/never_block/#{base}"
        Rainbows::NeverBlock.const_get(:Client).class_eval do
          self.superclass.const_set(:APP, G.server.app)
          include Rainbows::NeverBlock::Core
          alias _app_call app_call
          undef_method :app_call
          alias app_call nb_app_call
        end
      end

      def nb_app_call
        POOL.spawn do
          begin
            _app_call
          rescue => e
            handle_error(e)
          end
        end
      end

      def init_worker_process(worker)
        super
        Core.setup
        logger.info "NeverBlock/#{O[:backend]} pool_size=#{O[:pool_size]}"
      end
    end

    # :startdoc:

  end
end
