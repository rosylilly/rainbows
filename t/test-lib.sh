#!/bin/sh
# Copyright (c) 2009 Eric Wong
set -e
set -u
T=$(basename $0)
ruby="${ruby-ruby}"

# ensure a sane environment
TZ=UTC LC_ALL=C LANG=C
export LANG LC_ALL TZ
unset CDPATH

die () {
	echo >&2 "$@"
	exit 1
}

TEST_RM_LIST=""
trap 'rm -f $TEST_RM_LIST' 0
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

require_revactor () {
	if ! $ruby -rrevactor -e "puts Revactor::VERSION" >/dev/null 2>&1
	then
		echo >&2 "skipping $T since we don't have Revactor"
		exit 0
	fi
}
