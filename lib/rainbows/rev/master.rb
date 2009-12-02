# -*- encoding: binary -*-
require 'rainbows/rev'

RUBY_VERSION =~ %r{\A1\.8} && ::Rev::VERSION < "0.3.2" and
  warn "Rainbows::RevThreadSpawn + Rev (< 0.3.2)" \
       " does not work well under Ruby 1.8"

module Rainbows

  module Rev
    class Master < ::Rev::AsyncWatcher

      def initialize(queue)
        super()
        @queue = queue
      end

      def <<(output)
        @queue << output
        signal
      end

      def on_signal
        client, response = @queue.pop
        client.response_write(response)
      end
    end
  end
end
