#!/bin/sh
. ./test-lib.sh
require_rev

eval $(unused_listen)
rtmpfiles unicorn_config pid r_err r_out tmp fifo ok
rm -f $fifo
mkfifo $fifo

nr_client=30

cat > $unicorn_config <<EOF
listen "$listen"
pid "$pid"
stderr_path "$r_err"
stdout_path "$r_out"
Rainbows! do
  use :Rev
  worker_connections 50
end
EOF

rainbows -D t4000.ru -c $unicorn_config
wait_for_pid $pid

echo "single request"
curl -sSfv http://$listen/

echo "two requests with keepalive"
curl -sSfv http://$listen/a http://$listen/b > $tmp 2>&1
grep 'Re-using existing connection' < $tmp

echo "pipelining partial requests"
req='GET / HTTP/1.1\r\nHost: example.com\r\n'
(
	printf "$req"'\r\n'"$req"
	cat $fifo > $tmp &
	sleep 1
	printf 'Connection: close\r\n\r\n'
	wait
	echo ok > $ok
) | socat - TCP:$listen > $fifo

kill $(cat $pid)

test 2 -eq $(grep '^HTTP/1.1' $tmp | wc -l)
test 2 -eq $(grep '^HTTP/1.1 200 OK' $tmp | wc -l)
test 1 -eq $(grep '^Connection: keep-alive' $tmp | wc -l)
test 1 -eq $(grep '^Connection: close' $tmp | wc -l)
test x"$(cat $ok)" = xok
! grep Error $r_err
