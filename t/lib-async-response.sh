CONFIG_RU=${CONFIG_RU-'async-response.ru'}
. ./test-lib.sh
echo "async response for model=$model"
eval $(unused_listen)
rtmpfiles unicorn_config a b c r_err r_out pid curl_err

cat > $unicorn_config <<EOF
listen "$listen"
stderr_path "$r_err"
stdout_path "$r_out"
pid "$pid"
Rainbows! { use :$model }
EOF

# can't load Rack::Lint here since it'll cause Rev to slurp
rainbows -E none -D $CONFIG_RU -c $unicorn_config
wait_for_pid $pid

t0=$(date +%s)
( curl --no-buffer -sSf http://$listen/ 2>> $curl_err | utee $a) &
( curl --no-buffer -sSf http://$listen/ 2>> $curl_err | utee $b) &
( curl --no-buffer -sSf http://$listen/ 2>> $curl_err | utee $c) &
wait
t1=$(date +%s)

rainbows_pid=$(cat $pid)
kill -QUIT $rainbows_pid
elapsed=$(( $t1 - $t0 ))
echo "elapsed=$elapsed < 30"
test $elapsed -lt 30

dbgcat a
dbgcat b
dbgcat c
dbgcat r_err
dbgcat curl_err
test ! -s $curl_err
grep Error $r_err && die "errors in $r_err"

while kill -0 $rainbows_pid >/dev/null 2>&1
do
	sleep 1
done

dbgcat r_err
