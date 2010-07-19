# -*- encoding: binary -*-
# :enddoc:
#
# this is class is specific to Rev for writing large static files
# or proxying IO-derived objects
class Rainbows::Rev::DeferredResponse < ::Rev::IO
  def initialize(io, client, do_chunk, body)
    super(io)
    @client, @do_chunk, @body = client, do_chunk, body
  end

  def on_read(data)
    @do_chunk and @client.write("#{data.size.to_s(16)}\r\n")
    @client.write(data)
    @do_chunk and @client.write("\r\n")
  end

  def on_close
    @do_chunk and @client.write("0\r\n\r\n")
    @client.next
    @body.respond_to?(:close) and @body.close
  end
end
