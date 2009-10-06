#!/bin/sh
. ./test-lib.sh

eval $(unused_listen)
pid=$(mktemp -t rainbows.$$.pid.XXXXXXXX)
TEST_RM_LIST="$TEST_RM_LIST $lock_path $pid"

rainbows t0000.ru -l $listen --pid $pid &
wait_for_pid $pid
curl -sSfv http://$listen/
kill $(cat $pid)
