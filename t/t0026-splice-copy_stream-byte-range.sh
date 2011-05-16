#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
check_copy_stream
check_splice

t_plan 13 "IO::Splice.copy_stream byte range response for $model"

t_begin "setup and startup" && {
	rtmpfiles out err
	rainbows_setup $model
	cat >> $unicorn_config <<EOF
require "io/splice"
Rainbows! do
  copy_stream IO::Splice
end
def (::IO).copy_stream(*x); abort "NO"; end
EOF

	# can't load Rack::Lint here since it clobbers body#to_path
	rainbows -E none -D large-file-response.ru -c $unicorn_config
	rainbows_wait_start
}

. ./byte-range-common.sh
