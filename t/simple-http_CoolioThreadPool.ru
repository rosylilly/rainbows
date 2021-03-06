use Rack::ContentLength
use Rack::ContentType
run lambda { |env|
  if env['rack.multithread'] && env['rainbows.model'] == :CoolioThreadPool
    [ 200, {}, [ env.inspect << "\n" ] ]
  else
    raise "rack.multithread is false"
  end
}
