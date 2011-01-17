# -*- encoding: binary -*-
# :enddoc:
module Rainbows::EventMachine::ResponsePipe
  # garbage avoidance, EM always uses this in a single thread,
  # so a single buffer for all clients will work safely
  RBUF = Rainbows::EvCore::RBUF

  def initialize(client)
    @client = client
  end

  def notify_readable
    begin
      @client.write(@io.read_nonblock(16384, RBUF))
    rescue Errno::EINTR
    rescue Errno::EAGAIN
      return
    rescue EOFError
      detach
      return
    end while true
  end

  def unbind
    @client.next!
    @io.close unless @io.closed?
  end
end
