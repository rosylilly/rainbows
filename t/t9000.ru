use Rack::ContentLength
use Rack::ContentType
use Rainbows::AppPool, :size => ENV['APP_POOL_SIZE'].to_i
sleep_class = ENV['SLEEP_CLASS']
sleep_class = sleep_class ? Object.const_get(sleep_class) : Kernel
class Sleeper
  def call(env)
    sleep_class = ENV['SLEEP_CLASS']
    sleep_class = sleep_class ? Object.const_get(sleep_class) : Kernel
    sleep_class.sleep 1
    [ 200, {}, [ "#{object_id}\n" ] ]
  end
end
run Sleeper.new
