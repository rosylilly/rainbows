# -*- encoding: binary -*-
# :enddoc:
module Rainbows::ReadTimeout
  G = Rainbows::G # :nodoc:

  def wait_readable
    IO.select([self], nil, nil, G.kato)
  end

  # used for reading headers (respecting keepalive_timeout)
  def read_timeout(buf = "")
    expire = nil
    begin
      case rv = kgio_tryread(16384, buf)
      when :wait_readable
        now = Time.now.to_f
        if expire
          now > expire and return
        else
          expire = now + G.kato
        end
        wait_readable
      else
        return rv
      end
    end while true
  end
end
