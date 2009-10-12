#!/bin/sh
. ./test-lib.sh
require_revactor

eval $(unused_listen)
rtmpfiles unicorn_config curl_out curl_err pid fifo tmp ok r_err r_out

rm -f $fifo
mkfifo $fifo

cat > $unicorn_config <<EOF
stderr_path "$r_err"
stdout_path "$r_out"
listen "$listen"
pid "$pid"
Rainbows! do
  use :Revactor
end
EOF

rainbows -D t0000.ru -c $unicorn_config
wait_for_pid $pid

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

dbgcat tmp
test 2 -eq $(grep '^HTTP/1.1' $tmp | wc -l)
test 2 -eq $(grep '^HTTP/1.1 200 OK' $tmp | wc -l)
test 1 -eq $(grep '^Connection: keep-alive' $tmp | wc -l)
test 1 -eq $(grep '^Connection: close' $tmp | wc -l)
test x"$(cat $ok)" = xok
! grep Error $r_err
