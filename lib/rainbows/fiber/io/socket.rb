# -*- encoding: binary -*-
# :enddoc:
#
# A Fiber-aware Socket class, gives users the illusion of a synchronous
# interface that yields away from the current Fiber whenever
# the underlying descriptor is blocked on reads or write.
#
# It's not recommended to use any of this in your applications
# unless you're willing to accept breakage.  Most of this is very
# difficult-to-use, fragile and we don't have much time to devote to
# supporting these in the future.
class Rainbows::Fiber::IO::Socket < Kgio::Socket
  include Rainbows::Fiber::IO::Methods
end
