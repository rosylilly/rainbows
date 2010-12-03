#!/bin/sh
. ./test-lib.sh
t_plan 7 "rack.input pipelining test"

t_begin "setup and startup" && {
	rainbows_setup $model
        rtmpfiles req
	rainbows -D sha1.ru -c $unicorn_config
	body=hello
	body_size=$(printf $body | wc -c)
	body_sha1=$(printf $body | rsha1)
	rainbows_wait_start
}

t_begin "send pipelined identity requests" && {

	{
		printf 'PUT / HTTP/1.0\r\n'
		printf 'Connection: keep-alive\r\n'
		printf 'Content-Length: %d\r\n\r\n%s' $body_size $body
		printf 'PUT / HTTP/1.1\r\nHost: example.com\r\n'
		printf 'Content-Length: %d\r\n\r\n%s' $body_size $body
		printf 'PUT / HTTP/1.0\r\n'
		printf 'Content-Length: %d\r\n\r\n%s' $body_size $body
	} > $req
	(
		cat $fifo > $tmp &
		cat $req
		wait
		echo ok > $ok
	) | socat - TCP4:$listen > $fifo
	test x"$(cat $ok)" = xok
}

t_begin "check responses" && {
	dbgcat tmp
	test 3 -eq $(grep $body_sha1 $tmp | wc -l)
}

t_begin "send pipelined chunked requests" && {

	{
		printf 'PUT / HTTP/1.0\r\n'
		printf 'Connection: keep-alive\r\n'
		printf 'Transfer-Encoding: chunked\r\n\r\n'
		printf '%x\r\n%s\r\n0\r\n\r\n' $body_size $body
		printf 'PUT / HTTP/1.1\r\nHost: example.com\r\n'
		printf 'Transfer-Encoding: chunked\r\n\r\n'
		printf '%x\r\n%s\r\n0\r\n\r\n' $body_size $body
		printf 'PUT / HTTP/1.0\r\n'
		printf 'Transfer-Encoding: chunked\r\n\r\n'
		printf '%x\r\n%s\r\n0\r\n\r\n' $body_size $body
	} > $req
	(
		cat $fifo > $tmp &
		cat $req
		wait
		echo ok > $ok
	) | socat - TCP4:$listen > $fifo
	test x"$(cat $ok)" = xok
}

t_begin "check responses" && {
	dbgcat tmp
	test 3 -eq $(grep $body_sha1 $tmp | wc -l)
}

t_begin "kill server" && kill $rainbows_pid

t_begin "no errors in stderr log" && check_stderr

t_done
