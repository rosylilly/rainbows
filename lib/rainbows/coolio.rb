# -*- encoding: binary -*-
require 'rainbows/coolio_support'

# Implements a basic single-threaded event model with
# {Cool.io}[http://coolio.github.com/].  It is capable of handling
# thousands of simultaneous client connections, but with only a
# single-threaded app dispatch.  It is suited for slow clients and
# fast applications (applications that do not have slow network
# dependencies) or applications that use DevFdResponse for deferrable
# response bodies.  It does not require your Rack application to be
# thread-safe, reentrancy is only required for the DevFdResponse body
# generator.
#
# Compatibility: Whatever Cool.io itself supports, currently Ruby
# 1.8/1.9.
#
# This model does not implement as streaming "rack.input" which
# allows the Rack application to process data as it arrives.  This
# means "rack.input" will be fully buffered in memory or to a
# temporary file before the application is entered.
module Rainbows::Coolio
  # :stopdoc:
  # keep-alive timeout scoreboard
  KATO = {}

  # all connected clients
  CONN = {}

  if {}.respond_to?(:compare_by_identity)
    CONN.compare_by_identity
    KATO.compare_by_identity
  end

  autoload :Master, 'rainbows/coolio/master'
  autoload :ThreadClient, 'rainbows/coolio/thread_client'
  autoload :DeferredChunkResponse, 'rainbows/coolio/deferred_chunk_response'
  # :startdoc:
end
# :enddoc:
require 'rainbows/coolio/heartbeat'
require 'rainbows/coolio/server'
require 'rainbows/coolio/core'
require 'rainbows/coolio/deferred_response'
require 'rainbows/coolio/client'
Rainbows::Coolio.__send__ :include, Rainbows::Coolio::Core
