# -*- encoding: binary -*-
module Rainbows::Rev::Sendfile
  if IO.method_defined?(:sendfile_nonblock)
    F = Rainbows::StreamFile

    def to_sendfile(io)
      F[0, io]
    end

    def rev_sendfile(body)
      body.offset += @_io.sendfile_nonblock(body, body.offset, 0x10000)
      enable_write_watcher
      rescue Errno::EAGAIN
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
