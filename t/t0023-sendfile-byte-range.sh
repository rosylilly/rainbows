#!/bin/sh
. ./test-lib.sh
test -r random_blob || die "random_blob required, run with 'make $0'"
case $RUBY_ENGINE in
ruby) ;;
*)
	t_info "skipping $T since it can't load the sendfile gem, yet"
	exit 0
	;;
esac

case $model in
EventMachine|NeverBlock|Revactor)
	t_info "skipping $T since it's not compatible with $model"
	exit 0
	;;
*) ;;
esac

t_plan 7 "sendfile byte range response for $model"

t_begin "setup and startup" && {
	rtmpfiles out err
	rainbows_setup $model
	echo 'require "sendfile"' >> $unicorn_config
	echo 'def (::IO).copy_stream(*x); abort "NO"; end' >> $unicorn_config

	# can't load Rack::Lint here since it clobbers body#to_path
	rainbows -E none -D large-file-response.ru -c $unicorn_config
	rainbows_wait_start
	range_head=-r-365
	range_tail=-r155-
	range_mid=-r200-300
}

t_begin "read random blob sha1s" && {
	sha1_head=$(curl -sSf $range_head file://random_blob | rsha1)
	sha1_tail=$(curl -sSf $range_tail file://random_blob | rsha1)
	sha1_mid=$(curl -sSf $range_mid file://random_blob | rsha1)
}

t_begin "head range matches" && {
	sha1="$(curl -sSv $range_head http://$listen/random_blob | rsha1)"
	test x"$sha1_head" = x"$sha1"
}

t_begin "tail range matches" && {
	sha1="$(curl -sS $range_tail http://$listen/random_blob | rsha1)"
	test x"$sha1_tail" = x"$sha1"
}

t_begin "mid range matches" && {
	sha1="$(curl -sS $range_mid http://$listen/random_blob | rsha1)"
	test x"$sha1_mid" = x"$sha1"
}

t_begin "shutdown server" && {
	kill -QUIT $rainbows_pid
}

t_begin "check stderr" && check_stderr

t_done
