use Rack::ContentLength
use Rack::ContentType
run lambda { |env|
  Actor.sleep 1
  if env['rack.multithread'] == false && env['rainbows.model'] == :Revactor
    [ 200, {}, [ Thread.current.inspect << "\n" ] ]
  else
    raise "rack.multithread is true"
  end
}
