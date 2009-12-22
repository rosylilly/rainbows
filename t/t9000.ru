use Rack::ContentLength
use Rack::ContentType
use Rainbows::AppPool, :size => ENV['APP_POOL_SIZE'].to_i
class Sleeper
  def call(env)
    (case env['rainbows.model']
    when :FiberPool, :FiberSpawn
      Rainbows::Fiber
    when :Revactor
      Actor
    when :RevFiberSpawn
      Rainbows::Fiber::Rev
    else
      Kernel
    end).sleep(1)
    [ 200, {}, [ "#{object_id}\n" ] ]
  end
end
run Sleeper.new
