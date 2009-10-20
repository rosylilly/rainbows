. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
if ! grep -v ^VmRSS: /proc/self/status >/dev/null 2>&1
then
	echo >&2 "skipping, can't read RSS from /proc/self/status"
	exit 0
fi
echo "large file response slurp avoidance for model=$model"
eval $(unused_listen)
rtmpfiles unicorn_config tmp r_err r_out pid ok fifo

cat > $unicorn_config <<EOF
listen "$listen"
stderr_path "$r_err"
stdout_path "$r_out"
pid "$pid"
Rainbows! { use :$model }
EOF

# can't load Rack::Lint here since it'll cause Rev to slurp
rainbows -E none -D large-file-response.ru -c $unicorn_config
wait_for_pid $pid

random_blob_size=$(wc -c < random_blob)
curl -v http://$listen/rss
dbgcat r_err
rss_before=$(curl -sSfv http://$listen/rss)
echo "rss_before=$rss_before"

for i in a b c
do
	size=$( (curl -sSfv http://$listen/random_blob && echo ok >$ok) |wc -c)
	test $size -eq $random_blob_size
	test xok = x$(cat $ok)
done

echo "HTTP/1.0 test" # this was a problem during development
size=$( (curl -0 -sSfv http://$listen/random_blob && echo ok >$ok) |wc -c)
test $size -eq $random_blob_size
test xok = x$(cat $ok)

echo "HTTP/0.9 test"
(
	printf 'GET /random_blob\r\n'
	cat $fifo > $tmp &
	wait
	echo ok > $ok
) | socat - TCP:$listen > $fifo
cmp $tmp random_blob
test xok = x$(cat $ok)

dbgcat r_err
curl -v http://$listen/rss
rss_after=$(curl -sSfv http://$listen/rss)
echo "rss_after=$rss_after"
diff=$(( $rss_after - $rss_before ))
echo "test diff=$diff < orig=$random_blob_size"
kill -QUIT $(cat $pid)
test $diff -le $random_blob_size
dbgcat r_err
