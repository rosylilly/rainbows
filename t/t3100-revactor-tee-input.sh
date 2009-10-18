#!/bin/sh
nr_client=${nr_client-25}
nr_actor=${nr_actor-50}

. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"

eval $(unused_listen)
rtmpfiles unicorn_config curl_out curl_err r_err r_out pid

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

start=$(date +%s)
for i in $(awk "BEGIN{for(i=0;i<$nr_client;++i) print i}" </dev/null)
do
	(
		curl -sSf -T- http://$listen/$i \
		  < random_blob >> $curl_out 2>> $curl_err
	) &
done
wait
echo elapsed=$(( $(date +%s) - $start ))

kill $(cat $pid)
test $nr_client -eq $(wc -l < $curl_out)
test 1 -eq $(sort < $curl_out | uniq | wc -l)
blob_sha1=$( expr "$(sha1sum < random_blob)" : '\([a-f0-9]\+\)')
echo blob_sha1=$blob_sha1
test x"$blob_sha1" = x"$(sort < $curl_out | uniq)"
! grep Error $r_err
