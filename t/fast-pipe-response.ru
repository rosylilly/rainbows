# must be run without Rack::Lint since that clobbers to_path
use Rainbows::DevFdResponse
run(lambda { |env|
  env['rainbows.autochunk'] = false
  [ 200,
    {
      'X-Rainbows-Autochunk' => 'no',
      'Content-Length' => ::File.stat('random_blob').size.to_s,
      'Content-Type' => 'application/octet-stream',
    },
    IO.popen('cat random_blob', 'rb') ]
})
