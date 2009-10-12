use Rack::ContentLength
use Rack::ContentType
sleep_class = ENV['SLEEP_CLASS']
sleep_class = sleep_class ? Object.const_get(sleep_class) : Kernel
$stderr.puts "sleep_class=#{sleep_class.inspect}"
run lambda { |env|
  nr = 1
  env["PATH_INFO"] =~ %r{/([\d\.]+)\z} and nr = $1.to_f
  sleep_class.sleep(nr)
  [ 200, {}, [ "Hello\n" ] ]
}
