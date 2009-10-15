#!/bin/sh
. ./test-lib.sh
require_rev

eval $(unused_listen)
rtmpfiles unicorn_config tmp pid r_err r_out out
nr_client=10
cat > $unicorn_config <<EOF
listen "$listen"
stderr_path "$r_err"
stdout_path "$r_out"
pid "$pid"
Rainbows! do
  use :Rev
end
EOF

rainbows -D sleep.ru -c $unicorn_config
wait_for_pid $pid

for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
do
	(
		rtmpfiles fifo tmp
		rm -f $fifo
		mkfifo $fifo
		(
			printf 'GET /0 HTTP/1.1\r\n'
			cat $fifo > $tmp &
			sleep 1
			printf 'Host: example.com\r\n'
			sleep 1
			printf 'Connection: close\r\n'
			sleep 1
			printf '\r\n'
			wait
		) | socat - TCP:$listen > $fifo
		fgrep 'Hello' $tmp >> $out || :
		rm -f $fifo $tmp
	) &
done

sleep 2 # potentially racy :<
kill -QUIT $(cat $pid)
wait

test x"$(wc -l < $out)" = x$nr_client
nr=$(sort < $out | uniq | wc -l)
test "$nr" -eq 1

test x$(sort < $out | uniq) = xHello
! grep Error $r_err
