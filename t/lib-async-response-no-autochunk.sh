#!/bin/sh
CONFIG_RU=async-response-no-autochunk.ru
. ./lib-async-response.sh
test x"$(cat $a)" = x0123456789
test x"$(cat $b)" = x0123456789
test x"$(cat $c)" = x0123456789
