#!/bin/sh
. ./test-lib.sh
case $model in
ThreadSpawn|ThreadPool|RevThreadSpawn|RevThreadPool) ;;
*) t_info "$0 is only compatible with Thread*"; exit 0 ;;
esac

t_plan 5 "ThreadTimeout Rack middleware test for $model"

t_begin "configure and start" && {
	rtmpfiles curl_err
	rainbows_setup
	rainbows -D t9100.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "normal request should not timeout" && {
	test x"HI" = x"$(curl -sSf http://$listen/ 2>> $curl_err)"
}

t_begin "sleepy request times out with 408" && {
	rm -f $ok
	curl -sSf http://$listen/2 2>> $curl_err || > $ok
	test -e $ok
	grep 408 $curl_err
}

t_begin "kill server" && {
	kill $rainbows_pid
}

t_begin "no errors in Rainbows! stderr" && {
	check_stderr
}

t_done
