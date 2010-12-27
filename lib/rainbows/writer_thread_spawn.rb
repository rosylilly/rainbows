# -*- encoding: binary -*-
require 'thread'
# This concurrency model implements a single-threaded app dispatch and
# spawns a new thread for writing responses.  This concurrency model
# should be ideal for apps that serve large responses or stream
# responses slowly.
#
# Unlike most \Rainbows! concurrency models, WriterThreadSpawn is
# designed to run behind nginx just like Unicorn is.  This concurrency
# model may be useful for existing Unicorn users looking for more
# output concurrency than socket buffers can provide while still
# maintaining a single-threaded application dispatch (though if the
# response body is generated on-the-fly, it must be thread safe).
#
# For serving large or streaming responses, setting
# "proxy_buffering off" in nginx is recommended.  If your application
# does not handle uploads, then using any HTTP-aware proxy like
# haproxy is fine.  Using a non-HTTP-aware proxy will leave you
# vulnerable to slow client denial-of-service attacks.

module Rainbows::WriterThreadSpawn
  # :stopdoc:
  include Rainbows::Base

  def write_body(my_sock, body, range) # :nodoc:
    my_sock.queue_body(body, range)
  end

  def process_client(client) # :nodoc:
    super(Client.new(client))
  end

  def worker_loop(worker)  # :nodoc:
    Client.const_set(:MAX, worker_connections)
    super # accept loop from Unicorn
    Client.quit
  end
  # :startdoc:
end
# :enddoc:
require 'rainbows/writer_thread_spawn/client'
