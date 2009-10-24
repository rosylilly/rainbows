nr_client=${nr_client-4}
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"

rainbows_setup
rtmpfiles curl_out curl_err
rainbows -D sha1.ru -c $unicorn_config
rainbows_wait_start

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
check_stderr
