CONFIG_RU=${CONFIG_RU-'async-response.ru'}
. ./test-lib.sh
echo "async response for model=$model"
rtmpfiles a b c curl_err
rainbows_setup
# can't load Rack::Lint here since it'll cause Rev to slurp
rainbows -E none -D $CONFIG_RU -c $unicorn_config
rainbows_wait_start

t0=$(date +%s)
( curl --no-buffer -sSf http://$listen/ 2>> $curl_err | utee $a) &
( curl --no-buffer -sSf http://$listen/ 2>> $curl_err | utee $b) &
( curl --no-buffer -sSf http://$listen/ 2>> $curl_err | utee $c) &
wait
t1=$(date +%s)

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
check_stderr

while kill -0 $rainbows_pid >/dev/null 2>&1
do
	sleep 1
done

dbgcat r_err
