# we can run tests in parallel with GNU make

all::

RUBY = $(ruby)
rainbows_lib := $(shell cd ../lib && pwd)
-include ../local.mk
ifeq ($(RUBY_VERSION),)
  RUBY_VERSION := $(shell $(RUBY) -e 'puts RUBY_VERSION')
endif

ifeq ($(RUBYLIB),)
  RUBYLIB := $(rainbows_lib)
else
  RUBYLIB := $(rainbows_lib):$(RUBYLIB)
endif
export RUBYLIB RUBY_VERSION

T = $(wildcard t[0-9][0-9][0-9][0-9]-*.sh)

all:: $(T)

# can't rely on "set -o pipefail" since we don't require bash or ksh93 :<
t_pfx = trash/$@-$(RUBY_VERSION)
TEST_OPTS =
# TRACER = strace -f -o $(t_pfx).strace -s 100000
# TRACER = /usr/bin/time -o $(t_pfx).time
run_test = $(TRACER) $(SHELL) $(SH_TEST_OPTS) $@ $(TEST_OPTS)

ifdef V
  ifeq ($(V),2)
    TEST_OPTS += --trace
  else
    TEST_OPTS += --verbose
  endif
endif

test-bin-$(RUBY_VERSION)/rainbows: ruby_bin = $(shell which $(RUBY))
test-bin-$(RUBY_VERSION)/rainbows: ../bin/rainbows
	mkdir -p $(@D)
	install -m 755 $^ $@+
	$(RUBY) -i -p -e '$$_.gsub!(%r{^#!.*$$},"#!$(ruby_bin)")' $@+
	mv $@+ $@

req_random_blob := $(wildcard t?1??-*.sh)
random_blob:
	dd if=/dev/urandom bs=1M count=10 of=$@+
	mv $@+ $@

$(req_random_blob): random_blob

$(T): trash/.gitignore
$(T): export RUBY := $(RUBY)
$(T): export PATH := $(CURDIR)/test-bin-$(RUBY_VERSION):$(PATH)
$(T): test-bin-$(RUBY_VERSION)/rainbows
	@$(run_test)

trash/.gitignore:
	mkdir -p $(@D)
	echo '*' > $@

clean:
	$(RM) -r trash/*.log trash/*.code test-bin-$(RUBY_VERSION)

.PHONY: $(T) clean
