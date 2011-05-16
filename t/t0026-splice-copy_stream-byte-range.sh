#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
case $RUBY_VERSION in
1.9.*) ;;
*)
	t_info "skipping $T since it can't IO::Splice.copy_stream"
	exit 0
	;;
esac
check_splice

case $model in
ThreadSpawn|WriterThreadSpawn|ThreadPool|WriterThreadPool|Base) ;;
XEpollThreadSpawn) ;;
*)
	t_info "skipping $T since it doesn't use copy_stream"
	exit 0
	;;
esac

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
