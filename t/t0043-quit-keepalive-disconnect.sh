#!/bin/sh
. ./test-lib.sh
case $model in
Coolio|CoolioThreadSpawn|CoolioThreadPool|EventMachine) ;;
Epoll|XEpoll|XEpollThreadPool|XEpollThreadSpawn) ;;
*)
	t_info "$0 not supported for $model"
	exit 0
	;;
esac

t_plan 7 "keepalive clients disconnected on SIGQUIT for $model"

t_begin "setup and start" && {
	rainbows_setup $model 50 30
	rainbows -E none -D env.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "start a keepalive request" && {
	(
		cat < $fifo > $tmp &
		printf 'GET / HTTP/1.1\r\nHost: example.com\r\n\r\n'
		wait
	) | socat - TCP4:$listen > $fifo &
}

t_begin "wait for response" && {
	while ! tail -1 < $tmp | grep '}$' >/dev/null
	do
		sleep 1
	done
}

t_begin "stop Rainbows! gracefully" && {
	t0=$(date +%s)
	kill -QUIT $rainbows_pid
}

t_begin "keepalive client disconnected quickly" && {
	wait
	diff=$(( $(date +%s) - $t0 ))
	test $diff -le 2 || die "client diff=$diff > 2"
}

t_begin "wait for termination" && {
	while kill -0 $rainbows_pid
	do
		sleep 1
	done
	diff=$(( $(date +%s) - $t0 ))
	test $diff -le 4 || die "server diff=$diff > 4"
}

t_begin "check stderr" && {
	check_stderr
}

t_done
