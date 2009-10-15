#!/bin/sh
nr_client=${nr_client-25}
nr=${nr-50}

. ./test-lib.sh
require_rev
test -r random_blob || die "random_blob required, run with 'make $0'"

eval $(unused_listen)
rtmpfiles unicorn_config tmp r_err r_out pid fifo ok
rm -f $fifo
mkfifo $fifo

cat > $unicorn_config <<EOF
listen "$listen"
pid "$pid"
stderr_path "$r_err"
stdout_path "$r_out"
Rainbows! do
  use :Rev
end
EOF

rainbows -D content-md5.ru -c $unicorn_config
wait_for_pid $pid

echo "small blob"
(
	echo hello world | content-md5-put
	cat $fifo > $tmp &
	wait
	echo ok > $ok
) | socat - TCP:$listen | tee $fifo

fgrep 'HTTP/1.1 200 OK' $tmp
test xok = x"$(cat $ok)"
! grep Error $r_err


echo "big blob"
(
	content-md5-put < random_blob
	cat $fifo > $tmp &
	wait
	echo ok > $ok
) | socat - TCP:$listen | tee $fifo

fgrep 'HTTP/1.1 200 OK' $tmp
test xok = x"$(cat $ok)"
! grep Error $r_err
kill $(cat $pid)
