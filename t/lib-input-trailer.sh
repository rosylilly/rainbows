. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"

t_plan 11 "input trailer test $model"

t_begin "setup and startup" && {
	rtmpfiles curl_out
	rainbows_setup $model
	rainbows -D content-md5.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "upload small blob" && {
	(
		cat $fifo > $tmp &
		echo hello world | content-md5-put
		wait
		echo ok > $ok
	) | socat - TCP:$listen > $fifo
	test xok = x"$(cat $ok)"
}

t_begin "HTTP response is OK" && fgrep 'HTTP/1.1 200 OK' $tmp
t_begin "no errors in stderr log" && check_stderr

t_begin "big blob request" && {
	(
		cat $fifo > $tmp &
		content-md5-put < random_blob
		wait
		echo ok > $ok
	) | socat - TCP:$listen > $fifo
	test xok = x"$(cat $ok)"
}

t_begin "HTTP response is OK" && fgrep 'HTTP/1.1 200 OK' $tmp
t_begin "no errors in stderr log" && check_stderr

t_begin "staggered blob upload" && {
	(
		cat $fifo > $tmp &
		(
			dd bs=164 count=1 < random_blob
			sleep 2
			dd bs=4545 count=1 < random_blob
			sleep 2
			dd bs=1234 count=1 < random_blob
			echo subok > $ok
		) 2>/dev/null | content-md5-put
		test xsubok = x"$(cat $ok)"
		wait
		echo ok > $ok
	) | socat - TCP:$listen > $fifo
	test xok = x"$(cat $ok)"
}

t_begin "HTTP response is OK" && {
	fgrep 'HTTP/1.1 200 OK' $tmp
}

t_begin "no errors in stderr log" && check_stderr

t_begin "kill server" && {
	kill $rainbows_pid
}

t_done
