#!/bin/sh
. ./test-lib.sh
require_revactor

eval $(unused_listen)
rtmpfiles unicorn_config curl_out curl_err pid r_err r_out r_rot

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

SLEEP_CLASS=Actor rainbows -D sleep.ru -c $unicorn_config
wait_for_pid $pid

start=$(date +%s)
for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
do
	( curl -sSf http://$listen/2 >> $curl_out 2>> $curl_err ) &
done
! grep Error $r_err

rm $r_rot
mv $r_err $r_rot

kill -USR1 $(cat $pid)
wait_for_pid $r_err

dbgcat r_rot
dbgcat r_err

wait
echo elapsed=$(( $(date +%s) - $start ))
! test -s $curl_err
test x"$(wc -l < $curl_out)" = x$nr_client
nr=$(sort < $curl_out | uniq | wc -l)

test "$nr" -eq 1
test x$(sort < $curl_out | uniq) = xHello
! grep Error $r_err
! grep Error $r_rot

kill $(cat $pid)
dbgcat r_err
! grep Error $r_err
