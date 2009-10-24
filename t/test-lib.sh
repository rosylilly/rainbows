#!/bin/sh
# Copyright (c) 2009 Rainbows! developers

# pipefail is non-POSIX, but useful in ksh/bash
(
	set +e
	set -o pipefail 2>/dev/null
)
if test $? -eq 0
then
	set -o pipefail
else
	echo >&2 "WARNING: your shell does not understand pipefail"
fi

set -e

T=$(basename $0)
if test -z "$model"
then
	case $T in
	t1???-thread-pool-*.sh) model=ThreadPool ;;
	t2???-thread-spawn-*.sh) model=ThreadSpawn ;;
	t3???-revactor-*.sh) model=Revactor ;;
	t4???-rev-*.sh) model=Rev ;;
	*) model=any ;;
	esac
fi

RUBY="${RUBY-ruby}"
RUBY_VERSION=${RUBY_VERSION-$($RUBY -e 'puts RUBY_VERSION')}
t_pfx=$PWD/trash/$T-$RUBY_VERSION
set -u

# ensure a sane environment
TZ=UTC LC_ALL=C LANG=C
export LANG LC_ALL TZ
unset CDPATH

die () {
	echo >&2 "$@"
	exit 1
}

_test_on_exit () {
	code=$?
	case $code in
	0)
		echo "ok $T"
		rm -f $_TEST_OK_RM_LIST
	;;
	*) echo "not ok $T" ;;
	esac
	rm -f $_TEST_RM_LIST
	exit $code
}

_TEST_RM_LIST=
_TEST_OK_RM_LIST=
trap _test_on_exit EXIT
PATH=$PWD/bin:$PATH
export PATH

test -x $PWD/bin/unused_listen || die "must be run in 't' directory"

wait_for_pid () {
	path="$1"
	nr=30
	while ! test -s "$path" && test $nr -gt 0
	do
		nr=$(($nr - 1))
		sleep 1
	done
}

require_check () {
	lib=$1
	const=$2
	if ! $RUBY -r$lib -e "puts $const" >/dev/null 2>&1
	then
		echo >&2 "skipping $T since we don't have $lib"
		exit 0
	fi
}

# given a list of variable names, create temporary files and assign
# the pathnames to those variables
rtmpfiles () {
	for id in "$@"
	do
		name=$id
		_tmp=$t_pfx.$id
		eval "$id=$_tmp"

		case $name in
		*fifo)
			rm -f $_tmp
			mkfifo $_tmp
			_TEST_RM_LIST="$_TEST_RM_LIST $_tmp"
			;;
		*)
			> $_tmp
			_TEST_OK_RM_LIST="$_TEST_OK_RM_LIST $_tmp"
			;;
		esac
	done
}

dbgcat () {
	id=$1
	eval '_file=$'$id
	echo "==> $id <=="
	sed -e "s/^/$id:/" < $_file
}

check_stderr () {
	set +u
	_r_err=${1-${r_err}}
	set -u
	if grep Error $_r_err
	then
		die "Errors found in $_r_err"
	elif grep SIGKILL $_r_err
	then
		die "SIGKILL found in $_r_err"
	fi
}

case $model in
Rev) require_check rev Rev::VERSION ;;
Revactor) require_check revactor Revactor::VERSION ;;
esac
