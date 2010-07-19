#!/bin/sh
. ./test-lib.sh

t_plan 5 "close pipe response for $model"

t_begin "setup and startup" && {
	rtmpfiles err out
	rainbows_setup $model
	export fifo
	rainbows -E none -D close-pipe-response.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "single request matches" && {
	cat $fifo > $out &
	test x'hello world' = x"$(curl -sSfv 2> $err http://$listen/)"
}

t_begin "body.close called" && {
	wait # for cat $fifo
	grep CLOSING $out || die "body.close not logged"
}

t_begin "shutdown server" && {
	kill -QUIT $rainbows_pid
}

t_begin "check stderr" && check_stderr

t_done
