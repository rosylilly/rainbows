# -*- encoding: binary -*-
# :enddoc:
#
module Rainbows::SocketProxy
  def kgio_addr
    to_io.kgio_addr
  end

  def kgio_read(size, buf = "")
    to_io.kgio_read(size, buf)
  end

  def kgio_read!(size, buf = "")
    to_io.kgio_read!(size, buf)
  end

  def kgio_trywrite(buf)
    to_io.kgio_trywrite(buf)
  end

  def kgio_tryread(size, buf = "")
    to_io.kgio_tryread(size, buf)
  end

  def kgio_wait_readable(timeout = nil)
    to_io.kgio_wait_readable(timeout)
  end

  def timed_read(buf)
    to_io.timed_read(buf)
  end
end
