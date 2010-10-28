#!/bin/sh
. ./test-lib.sh
t_plan 8 "reload restore settings for $model"

t_begin "setup and start" && {
	rtmpfiles orig_config
	rainbows_setup
	cat $unicorn_config > $orig_config
	rainbows -D -c $unicorn_config -l $listen env.ru
	rainbows_wait_start
}

t_begin "HTTP request confirms we're running the correct model" && {
	curl -sSfv http://$listen/ | grep "\"rainbows.model\"=>:$model"
}

t_begin "clobber config and reload" && {
	cat > $unicorn_config <<EOF
stderr_path "$r_err"
EOF
	kill -HUP $rainbows_pid
	while ! egrep '(done|error) reloading' $r_err >/dev/null
	do
		sleep 1
	done

	grep 'done reloading' $r_err >/dev/null
}

t_begin "HTTP request confirms we're on the default model" && {
	curl -sSfv http://$listen/ | \
	  grep "\"rainbows.model\"=>:Base" >/dev/null
}

t_begin "restore config and reload" && {
	cat $orig_config > $unicorn_config
	> $r_err
	kill -HUP $rainbows_pid
	rainbows_wait_start
	while ! egrep '(done|error) reloading' $r_err >/dev/null
	do
		sleep 1
	done
	grep 'done reloading' $r_err >/dev/null
}

t_begin "HTTP request confirms we're back on the correct model" && {
	curl -sSfv http://$listen/ | \
	  grep "\"rainbows.model\"=>:$model" >/dev/null
}

t_begin "killing succeeds" && {
	kill $rainbows_pid
}

t_begin "check stderr" && {
	check_stderr
}

t_done
