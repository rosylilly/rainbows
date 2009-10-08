#!/bin/sh
. ./test-lib.sh

eval $(unused_listen)
rtmpfiles pid tmp ok fifo

rm -f $fifo
mkfifo $fifo

rainbows -D t0000.ru -l $listen --pid $pid &
wait_for_pid $pid

echo "single request"
curl -sSfv http://$listen/

echo "two requests with keepalive"
curl -sSfv http://$listen/a http://$listen/b > $tmp 2>&1
grep 'Re-using existing connection' < $tmp

echo "pipelining partial requests"
req='GET / HTTP/1.1\r\nHost: foo\r\n'
(
	printf "$req"'\r\n'"$req"
	cat $fifo > $tmp &
	sleep 1
	printf 'Connection: close\r\n\r\n'
	echo ok > $ok
) | socat - TCP:$listen > $fifo

kill $(cat $pid)

# sed -ne 's/^/------/p' < $tmp
test 2 -eq $(grep '^HTTP/1.1' $tmp | wc -l)
test 2 -eq $(grep '^HTTP/1.1 200 OK' $tmp | wc -l)
test 1 -eq $(grep '^Connection: keep-alive' $tmp | wc -l)
test 1 -eq $(grep '^Connection: close' $tmp | wc -l)
test x"$(cat $ok)" = xok
