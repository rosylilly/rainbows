# -*- encoding: binary -*-

# Middleware used to enforce client_max_body_size for TeeInput users.
#
# There is no need to configure this middleware manually, it will
# automatically be configured for you based on the client_max_body_size
# setting.
#
# For more fine-grained control, you may also define it per-endpoint in
# your Rack config.ru like this:
#
#        map "/limit_1M" do
#          use Rainbows::MaxBody, 1024*1024
#          run MyApp
#        end
#        map "/limit_10M" do
#          use Rainbows::MaxBody, 1024*1024*10
#          run MyApp
#        end
#
# This is only compatible with concurrency models that expose a streaming
# "rack.input" to the Rack application.  Thus it is NOT compatible with
# any of the following as they fully buffer the request body before
# the application dispatch:
#
# * :Coolio
# * :CoolioThreadPool
# * :CoolioThreadSpawn
# * :Epoll
# * :EventMachine
# * :NeverBlock
# * :Rev
# * :RevThreadPool
# * :RevThreadSpawn
# * :XEpoll
#
# However, the global Rainbows::Configurator#client_max_body_size is compatible
# with all concurrency models \Rainbows! supports.
class Rainbows::MaxBody

  # This is automatically called when used with Rack::Builder#use
  def initialize(app, limit = nil)
    case limit
    when Integer, nil
    else
      raise ArgumentError, "limit not an Integer"
    end
    @app, @limit = app, limit
  end

  # :stopdoc:
  RACK_INPUT = "rack.input".freeze
  CONTENT_LENGTH = "CONTENT_LENGTH"
  HTTP_TRANSFER_ENCODING = "HTTP_TRANSFER_ENCODING"

  # our main Rack middleware endpoint
  def call(env)
    @limit = Rainbows.server.client_max_body_size if nil == @limit
    catch(:rainbows_EFBIG) do
      len = env[CONTENT_LENGTH]
      if len && len.to_i > @limit
        return err
      elsif /\Achunked\z/i =~ env[HTTP_TRANSFER_ENCODING]
        limit_input!(env)
      end
      @app.call(env)
    end || err
  end

  # this is called after forking, so it won't ever affect the master
  # if it's reconfigured
  def self.setup # :nodoc:
    Rainbows.server.client_max_body_size or return
    case Rainbows.server.use
    when :Rev, :Coolio, :EventMachine, :NeverBlock,
         :RevThreadSpawn, :RevThreadPool,
         :CoolioThreadSpawn, :CoolioThreadPool,
         :Epoll, :XEpoll
      return
    end

    # force ourselves to the outermost middleware layer
    Rainbows.server.app = self.new(Rainbows.server.app)
  end

  # Rack response returned when there's an error
  def err # :nodoc:
    [ 413, { 'Content-Length' => '0', 'Content-Type' => 'text/plain' }, [] ]
  end

  def limit_input!(env)
    input = env[RACK_INPUT]
    klass = input.respond_to?(:rewind) ? RewindableWrapper : Wrapper
    env[RACK_INPUT] = klass.new(input, @limit)
  end

  # :startdoc:
end
require 'rainbows/max_body/wrapper'
require 'rainbows/max_body/rewindable_wrapper'
