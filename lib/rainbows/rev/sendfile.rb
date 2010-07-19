# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Rev::Sendfile
  if IO.method_defined?(:sendfile_nonblock)
    def rev_sendfile(body)
      body.offset += @_io.sendfile_nonblock(body, body.offset, 0x10000)
      enable_write_watcher
      rescue Errno::EAGAIN
        enable_write_watcher
    end
  else
    def rev_sendfile(body)
      write(body.to_io.sysread(0x4000))
    end
  end
end
