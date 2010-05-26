# -*- encoding: binary -*-
require 'thread'
module Rainbows

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

  module WriterThreadSpawn
    include Base

    CUR = {}

    # used to wrap a BasicSocket to use with +q+ for all writes
    # this is compatible with IO.select
    class MySocket < Struct.new(:to_io, :q, :thr)
      def readpartial(size, buf = "")
        to_io.readpartial(size, buf)
      end

      def write_nonblock(buf)
        to_io.write_nonblock(buf)
      end

      def queue_writer
        q = Queue.new
        self.thr = Thread.new(to_io, q) do |io, q|
          while response = q.shift
            begin
              arg1, arg2 = response
              case arg1
              when :body then Base.write_body(io, arg2)
              when :close
                io.close unless io.closed?
                break
              else
                io.write(arg1)
              end
            rescue => e
              Error.app(e)
            end
          end
          CUR.delete(Thread.current)
        end
        CUR[thr] = q
      end

      def write(buf)
        (self.q ||= queue_writer) << buf
      end

      def write_body(body)
        (self.q ||= queue_writer) << [ :body, body ]
      end

      def close
        if q
          q << :close
        else
          to_io.close
        end
      end

      def closed?
        false
      end
    end

    if IO.respond_to?(:copy_stream)
      undef_method :write_body

      def write_body(my_sock, body)
        my_sock.write_body(body)
      end
    end

    def process_client(client)
      super(MySocket[client])
    end

    def worker_loop(worker)
      super(worker) # accept loop from Unicorn
      CUR.delete_if do |t,q|
        q << nil
        G.tick
        t.alive? ? thr.join(0.01) : true
      end until CUR.empty?
    end
  end
end
