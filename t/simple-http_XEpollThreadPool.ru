use Rack::ContentLength
use Rack::ContentType
run lambda { |env|
  if env['rack.multithread'] == true &&
    env['rainbows.model'] == :XEpollThreadPool
    [ 200, {}, [ Thread.current.inspect << "\n" ] ]
  else
    raise env.inspect
  end
}
