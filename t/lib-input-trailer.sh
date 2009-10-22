. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
echo "input trailer test model=$model"

eval $(unused_listen)
rtmpfiles unicorn_config tmp r_err r_out pid fifo ok

cat > $unicorn_config <<EOF
listen "$listen"
pid "$pid"
stderr_path "$r_err"
stdout_path "$r_out"
Rainbows! { use :$model }
EOF

rainbows -D content-md5.ru -c $unicorn_config
wait_for_pid $pid

echo "small blob"
(
	cat $fifo > $tmp &
	echo hello world | content-md5-put
	wait
	echo ok > $ok
) | socat - TCP:$listen > $fifo

fgrep 'HTTP/1.1 200 OK' $tmp
test xok = x"$(cat $ok)"
check_stderr

echo "big blob"
(
	cat $fifo > $tmp &
	content-md5-put < random_blob
	wait
	echo ok > $ok
) | socat - TCP:$listen > $fifo

fgrep 'HTTP/1.1 200 OK' $tmp
test xok = x"$(cat $ok)"
check_stderr

echo "staggered blob"
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

fgrep 'HTTP/1.1 200 OK' $tmp
test xok = x"$(cat $ok)"
check_stderr

kill $(cat $pid)
