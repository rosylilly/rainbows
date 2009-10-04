#!/bin/sh
. ./test-lib.sh
require_revactor

eval $(unused_listen)
config_ru=$(mktemp -t rainbows.$$.XXXXXXXX.config.ru)
unicorn_config=$(mktemp -t rainbows.$$.XXXXXXXX.unicorn.rb)
curl_out=$(mktemp -t rainbows.$$.XXXXXXXX.curl.out)
curl_err=$(mktemp -t rainbows.$$.XXXXXXXX.curl.err)
pid=$(mktemp -t rainbows.$$.XXXXXXXX.pid)
TEST_RM_LIST="$TEST_RM_LIST $config_ru $unicorn_config $lock_path"
TEST_RM_LIST="$TEST_RM_LIST $curl_out $curl_err"

cat > $config_ru <<\EOF
use Rack::ContentLength
use Rack::ContentType
run lambda { |env|
  Actor.sleep 1
  [ 200, {}, [ Thread.current.inspect << "\n" ] ]
}
EOF

nr_client=30
nr_actor=10

cat > $unicorn_config <<EOF
listen "$listen"
pid "$pid"
Rainbows! do
  use :Revactor
  worker_connections $nr_actor
end
EOF

rainbows -D $config_ru -c $unicorn_config
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
