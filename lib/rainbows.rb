# -*- encoding: binary -*-
require 'unicorn'

module Rainbows

  require 'rainbows/const'
  require 'rainbows/http_server'
  require 'rainbows/http_response'
  require 'rainbows/base'

  class << self

    # runs the Rainbows! HttpServer with +app+ and +options+ and does
    # not return until the server has exited.
    def run(app, options = {})
      HttpServer.new(app, options).start.join
    end
  end

  # configures Rainbows! with a given concurrency model to +use+ and
  # a +worker_connections+ upper-bound.  This method may be called
  # inside a Unicorn/Rainbows configuration file:
  #
  #   Rainbows! do
  #     use :Revactor # this may also be :ThreadSpawn or :ThreadPool
  #     worker_connections 128
  #   end
  #
  # See the documentation for the respective Revactor, ThreadSpawn,
  # and ThreadPool classes for descriptions and recommendations for
  # each of them.
  def Rainbows!(&block)
    block_given? or raise ArgumentError, "Rainbows! requires a block"
    HttpServer.setup(block)
  end

  # maps models to default worker counts, default worker count numbers are
  # pretty arbitrary and tuning them to your application and hardware is
  # highly recommended
  MODEL_WORKER_CONNECTIONS = {
    :Base => 1, # this one can't change
    :Revactor => 50,
    :ThreadSpawn => 30,
    :ThreadPool => 10,
  }.each do |model, _|
    u = model.to_s.gsub(/([a-z0-9])([A-Z0-9])/) { "#{$1}_#{$2.downcase!}" }
    autoload model, "rainbows/#{u.downcase!}"
  end

end

# inject the Rainbows! method into Unicorn::Configurator
Unicorn::Configurator.class_eval { include Rainbows }
