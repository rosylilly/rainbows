# -*- encoding: binary -*-

module Rainbows::Fiber::IO::Methods
  RD = Rainbows::Fiber::RD
  WR = Rainbows::Fiber::WR
  attr_accessor :f

  # for wrapping output response bodies
  def each(&block)
    if buf = kgio_read(16384)
      yield buf
      yield buf while kgio_read(16384, buf)
    end
    self
  end

  def close
    fd = fileno
    RD[fd] = WR[fd] = nil
    super
  end

  def wait_readable
    fd = fileno
    @f = Fiber.current
    RD[fd] = self
    Fiber.yield
    RD[fd] = nil
  end

  def wait_writable
    fd = fileno
    @f = Fiber.current
    WR[fd] = self
    Fiber.yield
    WR[fd] = nil
  end

  def self.included(klass)
    if klass.method_defined?(:kgio_write)
      klass.__send__(:alias_method, :write, :kgio_write)
    end
  end
end
