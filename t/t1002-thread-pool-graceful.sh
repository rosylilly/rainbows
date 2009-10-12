#!/bin/sh
. ./test-lib.sh

eval $(unused_listen)
rtmpfiles unicorn_config curl_out curl_err pid r_err r_out
nr_thread=10
nr_client=10
cat > $unicorn_config <<EOF
listen "$listen"
stderr_path "$r_err"
stdout_path "$r_out"
pid "$pid"
Rainbows! do
  use :ThreadPool
  worker_connections $nr_thread
end
EOF

rainbows -D sleep.ru -c $unicorn_config
wait_for_pid $pid

for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
do
	curl -sSf http://$listen/5 >> $curl_out 2>> $curl_err &
done
sleep 2
kill -QUIT $(cat $pid)
wait

dbgcat r_err
! test -s $curl_err
test x"$(wc -l < $curl_out)" = x$nr_client
nr=$(sort < $curl_out | uniq | wc -l)

test "$nr" -eq 1
test x$(sort < $curl_out | uniq) = xHello
grep -v Error $r_err
