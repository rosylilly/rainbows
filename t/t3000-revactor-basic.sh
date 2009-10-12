#!/bin/sh
. ./test-lib.sh
require_revactor

eval $(unused_listen)
rtmpfiles unicorn_config curl_out curl_err pid r_err r_out

nr_client=30
nr_actor=10

cat > $unicorn_config <<EOF
listen "$listen"
pid "$pid"
stderr_path "$r_err"
stdout_path "$r_out"
Rainbows! do
  use :Revactor
  worker_connections $nr_actor
end
EOF

rainbows -D t3000.ru -c $unicorn_config
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

test "$nr" -eq 1
! grep Error $r_err
