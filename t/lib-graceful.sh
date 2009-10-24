. ./test-lib.sh
echo "graceful test for model=$model"

rtmpfiles curl_out
rainbows_setup
rainbows -D sleep.ru -c $unicorn_config
rainbows_wait_start

curl -sSfv -T- </dev/null http://$listen/5 > $curl_out 2> $fifo &

awk -v rainbows_pid=$rainbows_pid '
{ print $0 }
/100 Continue/ {
	print "awk: sending SIGQUIT to", rainbows_pid
	system("kill -QUIT "rainbows_pid)
}' $fifo
wait

dbgcat r_err

test x"$(wc -l < $curl_out)" = x1
nr=$(sort < $curl_out | uniq | wc -l)

test "$nr" -eq 1
test x$(sort < $curl_out | uniq) = xHello
check_stderr
while kill -0 $rainbows_pid >/dev/null 2>&1
do
	sleep 1
done
