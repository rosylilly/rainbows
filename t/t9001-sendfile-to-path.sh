#!/bin/sh
. ./test-lib.sh

t_plan 7 "Sendfile middleware test for $model"

t_begin "configure and start" && {
	rtmpfiles curl_out curl_err
	rainbows_setup

	# do not allow default middleware to be loaded since it may
	# kill body#to_path
	rainbows -E none -D t9001.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "hit with curl" && {
	curl -sSfv http://$listen/ > $curl_out 2> $curl_err
}

t_begin "kill server" && {
	kill $rainbows_pid
}

t_begin "file matches source" && {
	cmp $curl_out random_blob
}

t_begin "no errors in Rainbows! stderr" && {
	check_stderr
}

t_begin "X-Sendfile does not show up in headers" && {
	dbgcat curl_err
	if grep -i x-sendfile $curl_err
	then
		die "X-Sendfile did show up!"
	fi
}

t_begin "Content-Length is set correctly in headers" && {
	expect=$(wc -c < random_blob)
	grep "^< Content-Length: $expect" $curl_err
}

t_done
