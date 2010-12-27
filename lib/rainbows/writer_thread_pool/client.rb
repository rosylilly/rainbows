# -*- encoding: binary -*-
# :enddoc:
# used to wrap a BasicSocket to use with +q+ for all writes
# this is compatible with IO.select
class Rainbows::WriterThreadPool::Client < Struct.new(:to_io, :q)
  include Rainbows::SocketProxy

  def write(buf)
    q << [ to_io, buf ]
  end

  def close
    q << [ to_io, :close ]
  end

  def closed?
    false
  end
end
