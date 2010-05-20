#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
req_curl_chunked_upload_err_check

t_plan 6 "rack.input client_max_body_size tiny"

t_begin "setup and startup" && {
	rtmpfiles curl_out curl_err cmbs_config
	rainbows_setup $model
	sed -e 's/client_max_body_size.*/client_max_body_size 256/' \
	  < $unicorn_config > $cmbs_config
	rainbows -D sha1-random-size.ru -c $cmbs_config
	rainbows_wait_start
}

t_begin "stops a regular request" && {
	rm -f $ok
	dd if=/dev/zero bs=257 count=1 of=$tmp
	curl -vsSf -T $tmp -H Expect: \
	  http://$listen/ > $curl_out 2> $curl_err || > $ok
	dbgcat curl_err
	dbgcat curl_out
	test -e $ok
}

t_begin "stops a large chunked request" && {
	rm -f $ok
	dd if=/dev/zero bs=257 count=1 | \
	  curl -vsSf -T- -H Expect: \
	  http://$listen/ > $curl_out 2> $curl_err || > $ok
	dbgcat curl_err
	dbgcat curl_out
	test -e $ok
}

t_begin "small size sha1 chunked ok" && {
	blob_sha1=b376885ac8452b6cbf9ced81b1080bfd570d9b91
	rm -f $ok
	dd if=/dev/zero bs=256 count=1 | \
	  curl -vsSf -T- -H Expect: \
	  http://$listen/ > $curl_out 2> $curl_err
	dbgcat curl_err
	dbgcat curl_out
	test "$(cat $curl_out)" = $blob_sha1
}

t_begin "small size sha1 content-length ok" && {
	blob_sha1=b376885ac8452b6cbf9ced81b1080bfd570d9b91
	rm -f $ok
	dd if=/dev/zero bs=256 count=1 of=$tmp
	curl -vsSf -T $tmp -H Expect: \
	  http://$listen/ > $curl_out 2> $curl_err
	dbgcat curl_err
	dbgcat curl_out
	test "$(cat $curl_out)" = $blob_sha1
}

t_begin "shutdown" && {
	kill $rainbows_pid
}

t_done
