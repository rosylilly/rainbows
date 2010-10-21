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

    CUR = {} # :nodoc:

    # used to wrap a BasicSocket to use with +q+ for all writes
    # this is compatible with IO.select
    class MySocket < Struct.new(:to_io, :q, :thr)  # :nodoc: all
      include Rainbows::Response

      def readpartial(size, buf = "")
        to_io.readpartial(size, buf)
      end

      def kgio_read(size, buf = "")
        to_io.kgio_read(size, buf)
      end

      def kgio_read!(size, buf = "")
        to_io.kgio_read!(size, buf)
      end

      def write_nonblock(buf)
        to_io.write_nonblock(buf)
      end

      def queue_writer
        # not using Thread.pass here because that spins the CPU during
        # I/O wait and will eat cycles from other worker processes.
        until CUR.size < MAX
          CUR.delete_if { |t,_|
            t.alive? ? t.join(0) : true
          }.size >= MAX and sleep(0.01)
        end

        q = Queue.new
        self.thr = Thread.new(to_io, q) do |io, q|
          while response = q.shift
            begin
              arg1, arg2, arg3 = response
              case arg1
              when :body then write_body(io, arg2, arg3)
              when :close
                io.close unless io.closed?
                break
              else
                io.write(arg1)
              end
            rescue => e
              Error.write(io, e)
            end
          end
          CUR.delete(Thread.current)
        end
        CUR[thr] = q
      end

      def write(buf)
        (self.q ||= queue_writer) << buf
      end

      def queue_body(body, range)
        (self.q ||= queue_writer) << [ :body, body, range ]
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

    def write_body(my_sock, body, range) # :nodoc:
      my_sock.queue_body(body, range)
    end

    def process_client(client) # :nodoc:
      super(MySocket[client])
    end

    def worker_loop(worker)  # :nodoc:
      MySocket.const_set(:MAX, worker_connections)
      super(worker) # accept loop from Unicorn
      CUR.delete_if do |t,q|
        q << nil
        G.tick
        t.alive? ? t.join(0.01) : true
      end until CUR.empty?
    end
  end
end
