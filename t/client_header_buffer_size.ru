use Rack::ContentLength
use Rack::ContentType, "text/plain"
run lambda { |env|
  [ 200, {}, [ "#{Rainbows.server.client_header_buffer_size}\n" ] ]
}
