#!/bin/sh
. ./test-lib.sh

eval $(unused_listen)
rtmpfiles unicorn_config curl_out curl_err pid r_err r_out

nr_client=30
nr_thread=10

cat > $unicorn_config <<EOF
stderr_path "$r_err"
stdout_path "$r_out"
listen "$listen"
pid "$pid"
Rainbows! do
  use :ThreadPool
  worker_connections $nr_thread
end
EOF

rainbows -D t1000.ru -c $unicorn_config
wait_for_pid $pid

start=$(date +%s)
for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
do
	( curl -sSf http://$listen/$i >> $curl_out 2>> $curl_err ) &
done
wait
echo elapsed=$(( $(date +%s) - $start ))

kill $(cat $pid)

! test -s $curl_err
test x"$(wc -l < $curl_out)" = x$nr_client

nr=$(sort < $curl_out | uniq | wc -l)

test "$nr" -le $nr_thread
test "$nr" -gt 1

! grep Error $r_err
