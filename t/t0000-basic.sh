#!/bin/sh
. ./test-lib.sh

eval $(unused_listen)
config_ru=$(mktemp -t rainbows.$$.XXXXXXXX.config.ru)
pid=$(mktemp -t rainbows.$$.XXXXXXXX.pid)
TEST_RM_LIST="$TEST_RM_LIST $config_ru $lock_path"

cat > $config_ru <<\EOF
use Rack::ContentLength
use Rack::ContentType
run lambda { |env| [ 200, {}, [ env.inspect << "\n" ] ] }
EOF

rainbows $config_ru -l $listen --pid $pid &
wait_for_pid $pid
curl -sSfv http://$listen/
kill $(cat $pid)
