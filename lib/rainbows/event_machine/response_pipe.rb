# -*- encoding: binary -*-
# :enddoc:
module Rainbows::EventMachine::ResponsePipe
  # garbage avoidance, EM always uses this in a single thread,
  # so a single buffer for all clients will work safely
  BUF = ''

  def initialize(client, alive, body)
    @client, @alive, @body = client, alive, body
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
    @client.body = nil
    @alive ? @client.on_read('') : @client.quit
    @body.close if @body.respond_to?(:close)
    @io.close unless @io.closed?
  end
end
