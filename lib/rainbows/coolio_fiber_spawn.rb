# -*- encoding: binary -*-
# :stopdoc:
Rainbows.const_set(:CoolioFiberSpawn, Rainbows::RevFiberSpawn)
# :startdoc:

# A combination of the Coolio and FiberSpawn models.  This allows Ruby
# 1.9 Fiber-based concurrency for application processing while
# exposing a synchronous execution model and using scalable network
# concurrency provided by Cool.io.  A "rack.input" is exposed as well
# being Sunshowers-compatible.  Applications are strongly advised to
# wrap all slow IO objects (sockets, pipes) using the
# Rainbows::Fiber::IO or a Cool.io-compatible class whenever possible.
module Rainbows::CoolFiberSpawn; end
