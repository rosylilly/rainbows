require 'rack/fiber_pool'
use Rack::FiberPool
use Rack::ContentLength
use Rack::ContentType, 'text/plain'
run lambda { |env| [ 200, {}, [ "#{Fiber.current}\n" ] ] }
