#!/bin/sh
. ./test-lib.sh
STRACE=$(which strace 2>/dev/null || :)
if ! test -x "$STRACE"
then
	t_info "strace not found, skipping $T"
	exit 0
fi
if test x"$(uname -s)" != xLinux
then
	t_info "Linux is the only supported OS for $T"
	exit 0
fi

# these buffer internally in external libraries, so we can't detect when
# to use TCP_CORK
skip_models EventMachine NeverBlock
skip_models Coolio CoolioThreadPool CoolioThreadSpawn
skip_models Revactor Rev RevThreadPool RevThreadSpawn

# not sure why, but we don't have time to care about Ruby 1.8 too much
case $RUBY_VERSION in
1.8.*) skip_models WriterThreadSpawn WriterThreadPool ;;
esac

t_plan 13 "Kgio autopush tests"

t_begin "setup and start" && {
	rainbows_setup $model 1
	rtmpfiles strace_out
	ed -s $unicorn_config <<EOF
,s/^listen.*/listen "$listen", :tcp_nodelay => true, :tcp_nopush => true/
w
EOF
	rainbows -D large-file-response.ru -c $unicorn_config -E none
	rainbows_wait_start
}

t_begin "read worker pid" && {
	worker_pid=$(curl -sSf http://$listen/pid)
	kill -0 $worker_pid
}

t_begin "start strace on worker" && {
	strace -p $worker_pid -e '!futex' -f -o $strace_out &
	strace_pid=$!
	sleep 1
}

t_begin "reading RSS uncorks" && {
	curl -sSf http://$listen/rss >/dev/null
	sleep 2
	grep TCP_CORK $strace_out || :
	test 2 -eq $(grep TCP_CORK $strace_out |wc -l)
	fgrep 'SOL_TCP, TCP_CORK, [0], 4) = 0' $strace_out
	fgrep 'SOL_TCP, TCP_CORK, [1], 4) = 0' $strace_out
}

t_begin "restart strace on worker" && {
	kill -9 $strace_pid
	wait

	# dbgcat strace_out
	> $strace_out
	strace -p $worker_pid -e '!futex' -f -o $strace_out &
	strace_pid=$!
	sleep 1
}

t_begin "reading static file uncorks" && {
	curl -sSf http://$listen/random_blob >/dev/null
	sleep 2
	test 2 -eq $(grep TCP_CORK $strace_out |wc -l)
	fgrep 'SOL_TCP, TCP_CORK, [0], 4) = 0' $strace_out
	fgrep 'SOL_TCP, TCP_CORK, [1], 4) = 0' $strace_out
}

t_begin "stop strace on worker" && {
	kill -9 $strace_pid
	wait
}

t_begin "enable sendfile" && {
	echo >> $unicorn_config 'require "sendfile"'
	kill -HUP $rainbows_pid
	test xSTART = x"$(cat $fifo)"
}

t_begin "reread worker pid" && {
	worker_pid=$(curl -sSf http://$listen/pid)
	kill -0 $worker_pid
}

t_begin "restart strace on the worker" && {
	# dbgcat strace_out
	> $strace_out
	strace -p $worker_pid -e '!futex' -f -o $strace_out &
	strace_pid=$!
	sleep 1
}

t_begin "HTTP/1.x GET on static file with sendfile uncorks" && {
	curl -sSf http://$listen/random_blob >/dev/null
	sleep 1
	test 2 -eq $(grep TCP_CORK $strace_out |wc -l)
	fgrep 'SOL_TCP, TCP_CORK, [0], 4) = 0' $strace_out
	fgrep 'SOL_TCP, TCP_CORK, [1], 4) = 0' $strace_out
}

t_begin "killing succeeds" && {
	kill -9 $strace_pid
	wait
	# dbgcat strace_out
	kill $rainbows_pid
}

t_begin "check stderr" && check_stderr

t_done
