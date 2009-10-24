. ./test-lib.sh
echo "parser error test for model=$model"

rainbows_setup
rainbows -D env.ru -c $unicorn_config
rainbows_wait_start

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
