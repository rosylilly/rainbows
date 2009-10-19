#!/bin/sh
. ./test-lib.sh

eval $(unused_listen)
rtmpfiles unicorn_config pid r_err r_out curl_out curl_err

nr_client=30

cat > $unicorn_config <<EOF
listen "$listen"
pid "$pid"
stderr_path "$r_err"
stdout_path "$r_out"
Rainbows! do
  use :ThreadSpawn
  worker_connections 50
end
EOF

APP_POOL_SIZE=4
APP_POOL_SIZE=$APP_POOL_SIZE rainbows -D t9000.ru -c $unicorn_config
wait_for_pid $pid

start=$(date +%s)
for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
do
	( curl -sSf http://$listen/ >> $curl_out 2>> $curl_err ) &
done
wait
echo elapsed=$(( $(date +%s) - $start ))
kill $(cat $pid)

test $APP_POOL_SIZE -eq $(sort < $curl_out | uniq | wc -l)
test ! -s $curl_err

check_stderr
