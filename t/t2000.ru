use Rack::ContentLength
use Rack::ContentType
run lambda { |env|
  sleep 1
  if env['rack.multithread'] && env['rainbows.model'] == :ThreadSpawn
    [ 200, {}, [ Thread.current.inspect << "\n" ] ]
  else
    raise "rack.multithread is not true"
  end
}
