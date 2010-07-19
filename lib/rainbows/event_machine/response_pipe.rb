# -*- encoding: binary -*-
# :enddoc:
module Rainbows::EventMachine::ResponsePipe
  # garbage avoidance, EM always uses this in a single thread,
  # so a single buffer for all clients will work safely
  BUF = ''

  def initialize(client, alive)
    @client, @alive = client, alive
  end

  def notify_readable
    begin
      @client.write(@io.read_nonblock(16384, BUF))
    rescue Errno::EINTR
    rescue Errno::EAGAIN
      return
    rescue EOFError
      detach
      return
    end while true
  end

  def unbind
    @client.quit unless @alive
    @io.close
  end
end
