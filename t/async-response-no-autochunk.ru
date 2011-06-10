use Rack::Chunked
use Rainbows::DevFdResponse
script_chunked = <<-EOF
for i in 0 1 2 3 4 5 6 7 8 9
do
	printf '1\r\n%s\r\n' $i
	sleep 1
done
printf '0\r\n\r\n'
EOF

script_identity = <<-EOF
for i in 0 1 2 3 4 5 6 7 8 9
do
	printf $i
	sleep 1
done
EOF

run lambda { |env|
  env['rainbows.autochunk'] = false
  headers = { 'Content-Type' => 'text/plain' }

  script = case env["HTTP_VERSION"]
  when nil, "HTTP/1.0"
    script_identity
  else
    headers['Transfer-Encoding'] = 'chunked'
    script_chunked
  end

  [ 200, headers, IO.popen(script, 'rb') ].freeze
}
