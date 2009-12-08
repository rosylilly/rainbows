# -*- encoding: binary -*-
require 'rainbows/rev'

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
