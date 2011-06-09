require 'rainbows/server_token'
require 'rack/lobster'
use Rack::Head
use Rainbows::ServerToken
run Rack::Lobster.new
