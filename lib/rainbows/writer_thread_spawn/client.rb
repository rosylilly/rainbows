# -*- encoding: binary -*-
# :enddoc:
# used to wrap a BasicSocket to use with +q+ for all writes
# this is compatible with IO.select
class Rainbows::WriterThreadSpawn::Client < Struct.new(:to_io, :q, :thr)
  include Rainbows::Response
  include Rainbows::SocketProxy
  include Rainbows::WorkerYield

  CUR = {} # :nodoc:

  def self.quit
    g = Rainbows::G
    CUR.delete_if do |t,q|
      q << nil
      g.tick
      t.alive? ? t.join(0.01) : true
    end until CUR.empty?
  end

  def queue_writer
    until CUR.size < MAX
      CUR.delete_if { |t,_|
        t.alive? ? t.join(0) : true
      }.size >= MAX and worker_yield
    end

    q = Queue.new
    self.thr = Thread.new(to_io, q) do |io, q|
      while response = q.shift
        begin
          arg1, arg2, arg3 = response
          case arg1
          when :body then write_body(io, arg2, arg3)
          when :close
            io.close unless io.closed?
            break
          else
            io.write(arg1)
          end
        rescue => e
          Rainbows::Error.write(io, e)
        end
      end
      CUR.delete(Thread.current)
    end
    CUR[thr] = q
  end

  def write(buf)
    (self.q ||= queue_writer) << buf
  end

  def queue_body(body, range)
    (self.q ||= queue_writer) << [ :body, body, range ]
  end

  def close
    if q
      q << :close
    else
      to_io.close
    end
  end

  def closed?
    false
  end
end
