# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Coolio::Sendfile
  if IO.method_defined?(:sendfile_nonblock)
    def rev_sendfile(sf) # +sf+ is a Rainbows::StreamFile object
      sf.offset += (n = @_io.sendfile_nonblock(sf, sf.offset, sf.count))
      0 == (sf.count -= n) and raise EOFError
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
