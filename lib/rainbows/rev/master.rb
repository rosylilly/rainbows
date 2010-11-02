# -*- encoding: binary -*-
# :enddoc:
require 'rainbows/rev'

class Rainbows::Rev::Master < Rev::IOWatcher

  def initialize(queue)
    @reader, @writer = Kgio::Pipe.new
    super(@reader)
    @queue = queue
  end

  def <<(output)
    @queue << output
    @writer.kgio_trywrite("\0")
  end

  def on_readable
    if String === @reader.kgio_tryread(1)
      client, response = @queue.pop
      client.response_write(response)
    end
  end
end
