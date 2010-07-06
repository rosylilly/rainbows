# -*- encoding: binary -*-
module Rainbows
  module Fiber

    # A partially complete IO wrapper, this exports an IO.select()-able
    # #to_io method and gives users the illusion of a synchronous
    # interface that yields away from the current Fiber whenever
    # the underlying IO object cannot read or write
    class IO < Struct.new(:to_io, :f)
      include Rainbows::ByteSlice

      # :stopdoc:
      LOCALHOST = Unicorn::HttpRequest::LOCALHOST

      # needed to write errors with
      def write_nonblock(buf)
        to_io.write_nonblock(buf)
      end

      # enough for Rainbows.addr
      def peeraddr
        to_io.respond_to?(:peeraddr) ? to_io.peeraddr : [ LOCALHOST ]
      end
      # :stopdoc:

      # for wrapping output response bodies
      def each(&block)
        begin
          yield readpartial(16384)
        rescue EOFError
          break
        end while true
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
          (w = to_io.write_nonblock(buf)) == buf.bytesize and return
          buf = byte_slice(buf, w..-1)
        rescue Errno::EAGAIN
          wait_writable
          retry
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
        begin
          to_io.read_nonblock(length, buf)
        rescue Errno::EAGAIN
          wait_readable
          retry
        end
      end

    end
  end
end
