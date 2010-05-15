# -*- encoding: binary -*-

module Rainbows

  # This concurrency model implements a single-threaded app dispatch
  # with a separate thread pool for writing responses.  By default, this
  # thread pool is only a single thread: ideal for typical applications
  # that do not serve large or streaming responses.
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

  module WriterThreadPool
    include Base

    # used to wrap a BasicSocket to use with +q+ for all writes
    # this is compatible with IO.select
    class QueueSocket < Struct.new(:to_io, :q)
      def readpartial(size, buf = "")
        to_io.readpartial(size, buf)
      end

      def write_nonblock(buf)
        to_io.write_nonblock(buf)
      end

      def write(buf)
        q << [ to_io, buf ]
      end

      def close
        q << [ to_io, :close ]
      end

      def closed?
        false
      end
    end

    alias base_write_body write_body
    if IO.respond_to?(:copy_stream)
      undef_method :write_body

      def write_body(qclient, body)
        qclient.q << [ qclient.to_io, :body, body ]
      end
    end

    @@nr = 0
    @@q = nil

    def worker_loop(worker)
      # we have multiple, single-thread queues since we don't want to
      # interleave writes from the same client
      qp = (1..worker_connections).map do |n|
        QueuePool.new(1) do |response|
          begin
            io, arg1, arg2 = response
            case arg1
            when :body then base_write_body(io, arg2)
            when :close then io.close unless io.closed?
            else
              io.write(arg1)
            end
          rescue => err
            Error.app(err)
          end
        end
      end

      if qp.size == 1
        # avoid unnecessary calculations when there's only one queue,
        # most users should only need one queue...
        WriterThreadPool.module_eval do
          def process_client(client)
            super(QueueSocket[client, @@q])
          end
        end
        @@q = qp.first.queue
      else
        WriterThreadPool.module_eval do
          def process_client(client)
            @@nr += 1
            super(QueueSocket[client, @@q[@@nr %= @@q.size]])
          end
        end
        @@q = qp.map { |q| q.queue }
      end

      super(worker) # accept loop from Unicorn
      qp.map { |q| q.quit! }
    end
  end
end
