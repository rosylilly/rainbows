# -*- encoding: binary -*-

# This concurrency model implements a single-threaded app dispatch
# with a separate thread pool for writing responses.
#
# Unlike most \Rainbows! concurrency models, WriterThreadPool is
# designed to run behind nginx just like Unicorn is.  This concurrency
# model may be useful for existing Unicorn users looking for more
# output concurrency than socket buffers can provide while still
# maintaining a single-threaded application dispatch (though if the
# response body is dynamically generated, it must be thread safe).
#
# For serving large or streaming responses, using more threads (via
# the +worker_connections+ setting) and setting "proxy_buffering off"
# in nginx is recommended.  If your application does not handle
# uploads, then using any HTTP-aware proxy like haproxy is fine.
# Using a non-HTTP-aware proxy will leave you vulnerable to
# slow client denial-of-service attacks.
module Rainbows::WriterThreadPool
  # :stopdoc:
  include Rainbows::Base

  @@nr = 0
  @@q = nil

  def async_write_body(qclient, body, range)
    if body.respond_to?(:close)
      Rainbows::SyncClose.new(body) do |body|
        qclient.q << [ qclient.to_io, :body, body, range ]
      end
    else
      qclient.q << [ qclient.to_io, :body, body, range ]
    end
  end

  def process_client(client) # :nodoc:
    @@nr += 1
    super(Client.new(client, @@q[@@nr %= @@q.size]))
  end

  def init_worker_process(worker)
    super
    self.class.__send__(:alias_method, :sync_write_body, :write_body)
    Rainbows::WriterThreadPool.__send__(
                        :alias_method, :write_body, :async_write_body)
  end

  def worker_loop(worker) # :nodoc:
    # we have multiple, single-thread queues since we don't want to
    # interleave writes from the same client
    qp = (1..worker_connections).map do |n|
      Rainbows::QueuePool.new(1) do |response|
        begin
          io, arg1, arg2, arg3 = response
          case arg1
          when :body then sync_write_body(io, arg2, arg3)
          when :close then io.close unless io.closed?
          else
            io.write(arg1)
          end
        rescue => err
          Rainbows::Error.write(io, err)
        end
      end
    end

    @@q = qp.map { |q| q.queue }
    super(worker) # accept loop from Unicorn
    qp.map { |q| q.quit! }
  end
  # :startdoc:
end
# :enddoc:
require 'rainbows/writer_thread_pool/client'
