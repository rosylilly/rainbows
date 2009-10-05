# -*- encoding: binary -*-
require 'unicorn'

def Rainbows!(&block)
  block_given? or raise ArgumentError, "Rainbows! requires a block"
  Rainbows::HttpServer.setup(block)
end

module Rainbows

  require 'rainbows/const'
  require 'rainbows/http_server'
  require 'rainbows/http_response'
  require 'rainbows/base'

  class << self
    def run(app, options = {})
      HttpServer.new(app, options).start.join
    end
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
