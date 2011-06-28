# -*- encoding: binary -*-
# :enddoc:

# this class is used for most synchronous concurrency models
class Rainbows::Client < Kgio::Socket
  include Rainbows::ProcessClient
  Rainbows.config!(self, :keepalive_timeout)

  def read_expire
    Time.now + KEEPALIVE_TIMEOUT
  end

  # used for reading headers (respecting keepalive_timeout)
  def timed_read(buf)
    expire = nil
    begin
      case rv = kgio_tryread(CLIENT_HEADER_BUFFER_SIZE, buf)
      when :wait_readable
        return if expire && expire < Time.now
        expire ||= read_expire
        kgio_wait_readable(KEEPALIVE_TIMEOUT)
      else
        return rv
      end
    end while true
  end

  alias write kgio_write
end
