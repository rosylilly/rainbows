# -*- encoding: binary -*-

module Rainbows

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

  module WriterThreadPool
    include Base

    # used to wrap a BasicSocket to use with +q+ for all writes
    # this is compatible with IO.select
    class QueueSocket < Struct.new(:to_io, :q) # :nodoc:
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

    @@nr = 0
    @@q = nil

    def async_write_body(qclient, body, range)
      qclient.q << [ qclient.to_io, :body, body, range ]
    end

    def process_client(client) # :nodoc:
      @@nr += 1
      super(QueueSocket.new(client, @@q[@@nr %= @@q.size]))
    end

    def init_worker_process(worker)
      super
      self.class.__send__(:alias_method, :sync_write_body, :write_body)
      WriterThreadPool.__send__(:alias_method, :write_body, :async_write_body)
    end

    def worker_loop(worker) # :nodoc:
      # we have multiple, single-thread queues since we don't want to
      # interleave writes from the same client
      qp = (1..worker_connections).map do |n|
        QueuePool.new(1) do |response|
          begin
            io, arg1, arg2, arg3 = response
            case arg1
            when :body then sync_write_body(io, arg2, arg3)
            when :close then io.close unless io.closed?
            else
              io.write(arg1)
            end
          rescue => err
            Error.write(io, err)
          end
        end
      end

      @@q = qp.map { |q| q.queue }
      super(worker) # accept loop from Unicorn
      qp.map { |q| q.quit! }
    end
  end
end
