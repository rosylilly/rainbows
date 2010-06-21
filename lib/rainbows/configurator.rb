# -*- encoding: binary -*-
module Rainbows

  # This module adds \Rainbows! to the
  # {Unicorn::Configurator}[http://unicorn.bogomips.org/Unicorn/Configurator.html]
  module Configurator

    # configures \Rainbows! with a given concurrency model to +use+ and
    # a +worker_connections+ upper-bound.  This method may be called
    # inside a Unicorn/\Rainbows! configuration file:
    #
    #   Rainbows! do
    #     use :ThreadSpawn # concurrency model to use
    #     worker_connections 400
    #     keepalive_timeout 0 # zero disables keepalives entirely
    #     client_max_body_size 5*1024*1024 # 5 megabytes
    #   end
    #
    #   # the rest of the Unicorn configuration
    #   worker_processes 8
    #
    # See the documentation for the respective Revactor, ThreadSpawn,
    # and ThreadPool classes for descriptions and recommendations for
    # each of them.  The total number of clients we're able to serve is
    # +worker_processes+ * +worker_connections+, so in the above example
    # we can serve 8 * 400 = 3200 clients concurrently.
    #
    # The default is +keepalive_timeout+ is 5 seconds, which should be
    # enough under most conditions for browsers to render the page and
    # start retrieving extra elements for.  Increasing this beyond 5
    # seconds is not recommended.  Zero disables keepalive entirely
    # (but pipelining fully-formed requests is still works).
    #
    # The default +client_max_body_size+ is 1 megabyte (1024 * 1024 bytes),
    # setting this to +nil+ will disable body size checks and allow any
    # size to be specified.
    def Rainbows!(&block)
      block_given? or raise ArgumentError, "Rainbows! requires a block"
      HttpServer.setup(block)
    end

  end
end

# inject the Rainbows! method into Unicorn::Configurator
Unicorn::Configurator.class_eval { include Rainbows::Configurator }
