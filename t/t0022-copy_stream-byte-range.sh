#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
check_copy_stream

t_plan 13 "IO.copy_stream byte range response for $model"

t_begin "setup and startup" && {
	rtmpfiles out err
	rainbows_setup $model
	# can't load Rack::Lint here since it clobbers body#to_path
	rainbows -E none -D large-file-response.ru -c $unicorn_config
	rainbows_wait_start
}

. ./byte-range-common.sh
