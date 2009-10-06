use Rack::ContentLength
use Rack::ContentType
run lambda { |env|
  sleep 1
  [ 200, {}, [ Thread.current.inspect << "\n" ] ]
}
