#!/bin/sh
. ./test-lib.sh

t_plan 9 "heartbeat/timeout test for $model"

t_begin "setup and startup" && {
	rainbows_setup $model
        echo timeout 3 >> $unicorn_config
        echo preload_app true >> $unicorn_config
	rainbows -D heartbeat-timeout.ru -c $unicorn_config
	rainbows_wait_start
}

t_begin "read worker PID" && {
	worker_pid=$(curl -sSf http://$listen/)
	t_info "worker_pid=$worker_pid"
}

t_begin "sleep for a bit, ensure worker PID does not change" && {
	sleep 4
	test $(curl -sSf http://$listen/) -eq $worker_pid
}

t_begin "block the worker process to force it to die" && {
	t0=$(date +%s)
	err="$(curl -sSf http://$listen/block-forever 2>&1 || :)"
	t1=$(date +%s)
	elapsed=$(($t1 - $t0))
	t_info "elapsed=$elapsed err=$err"
	test x"$err" != x"Should never get here"
	test x"$err" != x"$worker_pid"
}

t_begin "ensure timeout took 3-6 seconds" && {
	test $elapsed -ge 3
	test $elapsed -le 6 # give it some slack in case box is bogged down
}

t_begin "wait for new worker to start up" && {
	test xSTART = x"$(cat $fifo)"
}

t_begin "we get a fresh new worker process" && {
	new_worker_pid=$(curl -sSf http://$listen/)
	test $new_worker_pid -ne $worker_pid
}

t_begin "SIGSTOP and SIGCONT on rainbows master does not kill worker" && {
	kill -STOP $rainbows_pid
	sleep 4
	kill -CONT $rainbows_pid
	sleep 2
	test $new_worker_pid -eq $(curl -sSf http://$listen/)
}

t_begin "stop server" && {
	kill $rainbows_pid
}

dbgcat r_err

t_done
