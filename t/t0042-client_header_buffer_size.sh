#!/bin/sh
. ./test-lib.sh

t_plan 8 "client_header_buffer_size tests for $model"

t_begin "setup and startup" && {
	rainbows_setup $model
}

t_begin "fails with zero buffer size" && {
	ed -s $unicorn_config <<EOF
,s/^  client_max_body_size.*/  client_header_buffer_size 0/
w
EOF
	grep "client_header_buffer_size 0" $unicorn_config
	rainbows -D client_header_buffer_size.ru -c $unicorn_config || \
		echo err=$? > $ok
	test x"$(cat $ok)" = "xerr=1"
}

t_begin "fails with negative value" && {
	ed -s $unicorn_config <<EOF
,s/^  client_header_buffer_size.*/  client_header_buffer_size -1/
w
EOF
	grep "client_header_buffer_size -1" $unicorn_config
	rainbows -D client_header_buffer_size.ru -c $unicorn_config || \
		echo err=$? > $ok
	test x"$(cat $ok)" = "xerr=1"
}

t_begin "fails with negative value" && {
	ed -s $unicorn_config <<EOF
,s/^  client_header_buffer_size.*/  client_header_buffer_size -1/
w
EOF
	grep "client_header_buffer_size -1" $unicorn_config
	rainbows -D client_header_buffer_size.ru -c $unicorn_config || \
		echo err=$? > $ok
	test x"$(cat $ok)" = "xerr=1"
}

t_begin "starts with correct value" && {
	ed -s $unicorn_config <<EOF
,s/^  client_header_buffer_size.*/  client_header_buffer_size 16399/
w
EOF
	grep "client_header_buffer_size 16399" $unicorn_config
	rainbows -D client_header_buffer_size.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "regular TCP request works right" && {
	test x$(curl -sSfv http://$listen/) = x16399
}

t_begin "no errors in stderr" && {
	check_stderr
}

t_begin "shutdown" && {
	kill $rainbows_pid
}

t_done
