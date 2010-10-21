# -*- encoding: binary -*-
module Rainbows
  module Fiber

    # A partially complete IO wrapper, this exports an IO.select()-able
    # #to_io method and gives users the illusion of a synchronous
    # interface that yields away from the current Fiber whenever
    # the underlying IO object cannot read or write
    #
    # TODO: subclass off IO and include Kgio::SocketMethods instead
    class IO < Struct.new(:to_io, :f)
      # :stopdoc:
      LOCALHOST = Kgio::LOCALHOST

      # needed to write errors with
      def write_nonblock(buf)
        to_io.write_nonblock(buf)
      end

      def kgio_addr
        to_io.kgio_addr
      end

      # for wrapping output response bodies
      def each(&block)
        if buf = readpartial(16384)
          yield buf
          yield buf while readpartial(16384, buf)
        end
        rescue EOFError
        self
      end

      def close
        fileno = to_io.fileno
        RD[fileno] = WR[fileno] = nil
        to_io.close unless to_io.closed?
      end

      def closed?
        to_io.closed?
      end

      def wait_readable
        fileno = to_io.fileno
        RD[fileno] = self
        ::Fiber.yield
        RD[fileno] = nil
      end

      def wait_writable
        fileno = to_io.fileno
        WR[fileno] = self
        ::Fiber.yield
        WR[fileno] = nil
      end

      def write(buf)
        begin
          case rv = to_io.kgio_trywrite(buf)
          when nil
            return
          when String
            buf = rv
          when Kgio::WaitWritable
            wait_writable
          end
        end while true
      end

      # used for reading headers (respecting keepalive_timeout)
      def read_timeout
        expire = nil
        begin
          to_io.read_nonblock(16384)
        rescue Errno::EAGAIN
          return if expire && expire < Time.now
          expire ||= Time.now + G.kato
          wait_readable
          retry
        end
      end

      def readpartial(length, buf = "")
        if to_io.respond_to?(:kgio_tryread)
          # TODO: use kgio_read!
          begin
            rv = to_io.kgio_tryread(length, buf)
            case rv
            when nil
              raise EOFError, "end of file reached", []
            when Kgio::WaitReadable
              wait_readable
            else
              return rv
            end
          end while true
        else
          begin
            to_io.read_nonblock(length, buf)
          rescue Errno::EAGAIN
            wait_readable
            retry
          end
        end
      end

      def kgio_read(*args)
        to_io.kgio_read(*args)
      end

      def kgio_read!(*args)
        to_io.kgio_read!(*args)
      end
    end
  end
end
