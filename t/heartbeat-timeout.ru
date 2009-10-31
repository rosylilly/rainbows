use Rack::ContentLength
fifo = ENV['FIFO_PATH'] or abort "FIFO_PATH not defined"
headers = { 'Content-Type' => 'text/plain' }
run lambda { |env|
  case env['PATH_INFO']
  when "/block-forever"
    # this should block forever (or until somebody opens it for reading)
    File.open(fifo, "rb") { |fp| fp.syswrite("NEVER\n") }
    [ 500, headers, [ "Should never get here\n" ] ]
  else
    [ 200, headers, [ "#$$\n" ] ]
  end
}
