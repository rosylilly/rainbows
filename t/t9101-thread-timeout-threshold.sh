#!/bin/sh
. ./test-lib.sh
case $model in
ThreadSpawn|ThreadPool|RevThreadSpawn|RevThreadPool) ;;
*) t_info "$0 is only compatible with Thread*"; exit 0 ;;
esac

t_plan 6 "ThreadTimeout Rack middleware test for $model"

t_begin "configure and start" && {
	rtmpfiles curl_err curl_out
	rainbows_setup $model 10
	rainbows -D t9101.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "normal request should not timeout" && {
	test x"HI" = x"$(curl -sSf http://$listen/ 2>> $curl_err)"
}

t_begin "8 sleepy requests do not time out" && {
	> $curl_err
	for i in 1 2 3 4 5 6 7 8
	do
		curl --no-buffer -sSf http://$listen/3 \
		  2>> $curl_err >> $curl_out &
	done
	wait
	test 8 -eq "$(wc -l < $curl_out)"
	test xHI = x"$(sort < $curl_out | uniq)"
}

t_begin "9 sleepy requests do time out" && {
	> $curl_err
	> $curl_out
	for i in 1 2 3 4 5 6 7 8 9
	do
		rtmpfiles curl_err_$i
		curl -sSf --no-buffer \
		  http://$listen/3 2>> ${curl_err}_${i} >> $curl_out &
	done
	wait
	if test -s $curl_out
	then
		dbgcat curl_out
		die "$curl_out should be empty"
	fi
	for i in 1 2 3 4 5 6 7 8 9
	do
		grep 408 ${curl_err}_${i}
	done
}

t_begin "kill server" && {
	kill $rainbows_pid
}

t_begin "no errors in Rainbows! stderr" && {
	check_stderr
}

t_done
