use Rack::ContentLength
use Rack::ContentType
run lambda { |env|
  if env['rack.multithread'] == true &&
     EM.reactor_running? &&
     env['rainbows.model'] == :EventMachineDefer
    [ 200, {}, [ env.inspect << "\n" ] ]
  else
    raise "incorrect parameters"
  end
}
