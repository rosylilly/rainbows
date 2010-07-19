# -*- encoding: binary -*-
# :enddoc:
module Rainbows::EventMachine::ResponseChunkPipe
  include Rainbows::EventMachine::ResponsePipe

  def unbind
    @client.write("0\r\n\r\n")
    super
  end

  def notify_readable
    begin
      data = @io.read_nonblock(16384, BUF)
      @client.write(sprintf("%x\r\n", data.size))
      @client.write(data)
      @client.write("\r\n")
    rescue Errno::EINTR
    rescue Errno::EAGAIN
      return
    rescue EOFError
      detach
      return
    end while true
  end
end
