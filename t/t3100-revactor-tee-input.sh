#!/bin/sh
nr_client=${nr_client-25}
nr_actor=${nr_actor-50}

. ./test-lib.sh
require_revactor

eval $(unused_listen)
unicorn_config=$(mktemp -t rainbows.$$.unicorn.rb.XXXXXXXX)
curl_out=$(mktemp -t rainbows.$$.curl.out.XXXXXXXX)
curl_err=$(mktemp -t rainbows.$$.curl.err.XXXXXXXX)
r_err=$(mktemp -t rainbows.$$.r.err.XXXXXXXX)
r_out=$(mktemp -t rainbows.$$.r.out.XXXXXXXX)
pid=$(mktemp -t rainbows.$$.pid.XXXXXXXX)
blob=$(mktemp -t rainbows.$$.blob.XXXXXXXX)
TEST_RM_LIST="$TEST_RM_LIST $unicorn_config $lock_path $r_err $r_out"
TEST_RM_LIST="$TEST_RM_LIST $curl_out $curl_err $blob"

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

echo pid=$pid
rainbows -D sha1.ru -c $unicorn_config
wait_for_pid $pid

dd if=/dev/urandom bs=1M count=10 of=$blob 2>/dev/null

start=$(date +%s)
for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
do
	( curl -sSf -T- < $blob http://$listen/$i >> $curl_out 2>> $curl_err ) &
done
wait
echo elapsed=$(( $(date +%s) - $start ))

kill $(cat $pid)
test $nr_client -eq $(wc -l < $curl_out)
test 1 -eq $(sort < $curl_out | uniq | wc -l)
blob_sha1=$( expr "$(sha1sum < $blob)" : '\([a-f0-9]\+\)')
echo blob_sha1=$blob_sha1
test x"$blob_sha1" = x"$(sort < $curl_out | uniq)"
