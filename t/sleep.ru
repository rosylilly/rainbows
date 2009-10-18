use Rack::ContentLength
use Rack::ContentType

run lambda { |env|
  nr = 1
  env["PATH_INFO"] =~ %r{/([\d\.]+)\z} and nr = $1.to_f

  (case env['rainbows.model']
  when :Revactor
    Actor
  else
    Kernel
  end).sleep(nr)

  [ 200, {}, [ "Hello\n" ] ]
}
