. ./test-lib.sh
echo "graceful test for model=$model"

eval $(unused_listen)
rtmpfiles unicorn_config curl_out pid r_err r_out fifo

cat > $unicorn_config <<EOF
listen "$listen"
stderr_path "$r_err"
stdout_path "$r_out"
pid "$pid"
Rainbows! { use :$model }
EOF

rainbows -D sleep.ru -c $unicorn_config
wait_for_pid $pid
rainbows_pid=$(cat $pid)

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
