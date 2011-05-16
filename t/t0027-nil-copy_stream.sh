#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
check_copy_stream

t_plan 7 "large file 'copy_stream nil' test for $model"

t_begin "setup and startup" && {
	rtmpfiles curl_out
	rainbows_setup $model
	cat >> $unicorn_config <<EOF
Rainbows! do
  copy_stream nil
end
EOF
	rainbows -E none -D large-file-response.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "read random blob sha1 and size" && {
	random_blob_sha1=$(rsha1 < random_blob)
	random_blob_size=$(wc -c < random_blob)
}

t_begin "send a series HTTP/1.1 requests sequentially" && {
	for i in a b c
	do
		sha1=$( (curl -sSfv http://$listen/random_blob &&
			 echo ok >$ok) | rsha1)
		test $sha1 = $random_blob_sha1
		test xok = x$(cat $ok)
	done
}

# this was a problem during development
t_begin "HTTP/1.0 test" && {
	sha1=$( (curl -0 -sSfv http://$listen/random_blob &&
	         echo ok >$ok) | rsha1)
	test $sha1 = $random_blob_sha1
	test xok = x$(cat $ok)
}

t_begin "HTTP/0.9 test" && {
	(
		printf 'GET /random_blob\r\n'
		rsha1 < $fifo > $tmp &
		wait
		echo ok > $ok
	) | socat - TCP:$listen > $fifo
	test $(cat $tmp) = $random_blob_sha1
	test xok = x$(cat $ok)
}

t_begin "shutdown server" && {
	kill -QUIT $rainbows_pid
}

t_begin "check stderr" && check_stderr

t_done
