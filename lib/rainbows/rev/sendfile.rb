# -*- encoding: binary -*-
module Rainbows::Rev::Sendfile
  if IO.method_defined?(:sendfile_nonblock)
    def rev_sendfile(body)
      body.pos += @_io.sendfile_nonblock(body, body.pos, 0x10000)
      rescue Errno::EAGAIN
      ensure
        enable_write_watcher
    end
  else
    def rev_sendfile(body)
      write(body.sysread(0x4000))
    end
  end
end
