#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
case $RUBY_ENGINE in
ruby) ;;
*)
	t_info "skipping $T since it can't load the sendfile gem, yet"
	exit 0
	;;
esac

t_plan 7 "large sendfile response for $model"

t_begin "setup and startup" && {
	rtmpfiles curl_out a b c
	rainbows_setup $model 2

	# FIXME: allow "require 'sendfile'" to work in $unicorn_config
	RUBYOPT="-rsendfile"
	export RUBYOPT

	# can't load Rack::Lint here since it clobbers body#to_path
	rainbows -E none -D large-file-response.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "read random blob sha1" && {
	random_blob_sha1=$(rsha1 < random_blob)
}

t_begin "send a series of HTTP/1.1 requests in parallel" && {
	for i in $a $b $c
	do
		(
			curl -sSf http://$listen/random_blob | rsha1 > $i
		) &
	done
	wait
	for i in $a $b $c
	do
		test x$(cat $i) = x$random_blob_sha1
	done
}

# this was a problem during development
t_begin "HTTP/1.0 test" && {
	sha1=$( (curl -0 -sSfv http://$listen/random_blob &&
	         echo ok >$ok) | rsha1)
	test $sha1 = $random_blob_sha1
	test xok = x$(cat $ok)
}

t_begin "HTTP/0.9 test" && {
	(
		printf 'GET /random_blob\r\n'
		rsha1 < $fifo > $tmp &
		wait
		echo ok > $ok
	) | socat - TCP:$listen > $fifo
	test $(cat $tmp) = $random_blob_sha1
	test xok = x$(cat $ok)
}

t_begin "shutdown server" && {
	kill -QUIT $rainbows_pid
}

dbgcat r_err

t_begin "check stderr" && check_stderr

t_done
