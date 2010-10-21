# -*- encoding: binary -*-
module Rainbows::Fiber::IO::Compat
  def initialize(io, fiber = Fiber.current)
    @to_io, @f = io, fiber
  end

  def close
    @to_io.close
  end
end
