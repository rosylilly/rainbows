. ./test-lib.sh
echo "parser error test for model=$model"

eval $(unused_listen)
rtmpfiles unicorn_config pid r_err r_out tmp fifo ok
rm -f $fifo
mkfifo $fifo

cat > $unicorn_config <<EOF
listen "$listen"
pid "$pid"
stderr_path "$r_err"
stdout_path "$r_out"
Rainbows! { use :$model }
EOF

rainbows -D env.ru -c $unicorn_config
wait_for_pid $pid

(
	printf 'GET / HTTP/1/1\r\nHost: example.com\r\n\r\n'
	cat $fifo > $tmp &
	wait
	echo ok > $ok
) | socat - TCP:$listen > $fifo

kill $(cat $pid)

dbgcat tmp
grep -F 'HTTP/1.1 400 Bad Request' $tmp
check_stderr
