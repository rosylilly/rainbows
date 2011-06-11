#!/bin/sh
. ./test-lib.sh
skip_models StreamResponseEpoll

t_plan 11 "client_max_header_size tests for $model"

t_begin "setup Rainbows!" && {
	rainbows_setup $model
}

t_begin "fails with zero size" && {
	ed -s $unicorn_config <<EOF
,s/^  client_max_body_size.*/  client_max_header_size 0/
w
EOF
	grep "client_max_header_size 0" $unicorn_config
	rainbows -D env.ru -c $unicorn_config && die "should fail"
}

t_begin "fails with negative value" && {
	ed -s $unicorn_config <<EOF
,s/^  client_max_header_size.*/  client_max_header_size -1/
w
EOF
	grep "client_max_header_size -1" $unicorn_config
	rainbows -D env.ru -c $unicorn_config && die "should fail"
}

t_begin "fails with small size" && {
	ed -s $unicorn_config <<EOF
,s/^  client_max_header_size.*/  client_max_header_size 7/
w
EOF
	grep "client_max_header_size 7" $unicorn_config
	rainbows -D env.ru -c $unicorn_config && die "should fail"
}

t_begin "starts with minimum value" && {
	ed -s $unicorn_config <<EOF
,s/^  client_max_header_size.*/  client_max_header_size 8/
w
EOF
	grep 'client_max_header_size 8$' $unicorn_config
	rainbows -D env.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "smallest HTTP/0.9 request works right" && {
	(
		cat $fifo > $tmp &
		printf 'GET /\r\n'
		wait
		echo ok > $ok
	) | socat - TCP:$listen > $fifo
	wait
	test xok = x"$(cat $ok)"
	test 1 -eq $(wc -l < $tmp)
	grep HTTP_VERSION $tmp && die "unexpected HTTP_VERSION in HTTP/0.9 request"
}

t_begin "HTTP/1.1 request fails" && {
	curl -vsSf http://$listen/ > $tmp 2>&1 && die "unexpected curl success"
	grep '400$' $tmp
}

t_begin "increase client_max_header_size on reload" && {
	ed -s $unicorn_config <<EOF
,s/^  client_max_header_size.*/  client_max_header_size 512/
w
EOF
	grep 'client_max_header_size 512$' $unicorn_config
	kill -HUP $rainbows_pid
	test xSTART = x"$(cat $fifo)"
}

t_begin "HTTP/1.1 request succeeds" && {
	curl -sSf http://$listen/ > $tmp
	test 1 -eq $(wc -l < $tmp)
	dbgcat tmp
}

t_begin "no errors in stderr" && {
	check_stderr
}

t_begin "shutdown" && {
	kill $rainbows_pid
}

t_done
