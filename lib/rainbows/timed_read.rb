# -*- encoding: binary -*-
# :enddoc:
module Rainbows::TimedRead
  G = Rainbows::G # :nodoc:

  def read_expire
    Time.now + G.kato
  end

  def kgio_wait_readable
    IO.select([self], nil, nil, G.kato)
  end

  # used for reading headers (respecting keepalive_timeout)
  def timed_read(buf)
    expire = nil
    begin
      case rv = kgio_tryread(16384, buf)
      when :wait_readable
        return if expire && expire < Time.now
        expire ||= read_expire
        kgio_wait_readable
      else
        return rv
      end
    end while true
  end
end
