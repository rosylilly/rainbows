# -*- encoding: binary -*-
module Rainbows::Rev::Sendfile
  if IO.method_defined?(:sendfile_nonblock)
    class F < Struct.new(:offset, :to_io)
      def close
        to_io.close
        self.to_io = nil
      end
    end

    def to_sendfile(io)
      F[0, io]
    end

    def rev_sendfile(body)
      body.offset += @_io.sendfile_nonblock(body, body.offset, 0x10000)
      rescue Errno::EAGAIN
      ensure
        enable_write_watcher
    end
  else
    def to_sendfile(io)
      io
    end

    def rev_sendfile(body)
      write(body.sysread(0x4000))
    end
  end
end
