. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
echo "input trailer test model=$model"
require_for_model

eval $(unused_listen)
rtmpfiles unicorn_config tmp r_err r_out pid fifo ok
rm -f $fifo
mkfifo $fifo

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
	echo hello world | content-md5-put
	cat $fifo > $tmp &
	wait
	echo ok > $ok
) | socat - TCP:$listen | utee $fifo

fgrep 'HTTP/1.1 200 OK' $tmp
test xok = x"$(cat $ok)"
! grep Error $r_err


echo "big blob"
(
	content-md5-put < random_blob
	cat $fifo > $tmp &
	wait
	echo ok > $ok
) | socat - TCP:$listen | utee $fifo

fgrep 'HTTP/1.1 200 OK' $tmp
test xok = x"$(cat $ok)"
! grep Error $r_err

echo "staggered blob"
(
	(
		dd bs=164 count=1 < random_blob
		sleep 2
		dd bs=4545 count=1 < random_blob
		sleep 2
		dd bs=1234 count=1 < random_blob
		echo ok > $ok
	) 2>/dev/null | content-md5-put
	test xok = x"$(cat $ok)"
	cat $fifo > $tmp &
	wait
	echo ok > $ok
) | socat - TCP:$listen | utee $fifo

fgrep 'HTTP/1.1 200 OK' $tmp
test xok = x"$(cat $ok)"
! grep Error $r_err


kill $(cat $pid)
