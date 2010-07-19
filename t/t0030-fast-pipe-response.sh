#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"

t_plan 6 "fast pipe response for $model"

t_begin "setup and startup" && {
	rtmpfiles err
	rainbows_setup $model
	rainbows -E none -D fast-pipe-response.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "read random blob sha1" && {
	random_blob_sha1=$(rsha1 < random_blob)
}

t_begin "single request matches" && {
	sha1=$(curl -sSfv 2> $err http://$listen/ | rsha1)
	test -n "$sha1"
	test x"$sha1" = x"$random_blob_sha1"
}

t_begin "Content-Length header preserved in response" && {
	grep "^< Content-Length:" $err
}

t_begin "shutdown server" && {
	kill -QUIT $rainbows_pid
}

dbgcat r_err

t_begin "check stderr" && check_stderr

t_done
