# -*- encoding: binary -*-
# :enddoc:
class Rainbows::Fiber::Coolio::Server < Coolio::IOWatcher
  G = Rainbows::G
  include Rainbows::ProcessClient

  def to_io
    @io
  end

  def initialize(io)
    @io = io
    super(self, :r)
  end

  def close
    detach if attached?
    @io.close
  end

  def on_readable
    return if G.cur >= MAX
    c = @io.kgio_tryaccept and Fiber.new { process(c) }.resume
  end

  def process(io)
    G.cur += 1
    process_client(io)
  ensure
    G.cur -= 1
  end
end
