# -*- encoding: binary -*-
# :enddoc:
class Rainbows::MaxBody::Wrapper
  def initialize(rack_input, limit)
    @input, @limit = rack_input, limit
  end

  def check(rv)
    throw :rainbows_EFBIG if rv && ((@limit -= rv.size) < 0)
    rv
  end

  def each(&block)
    while line = @input.gets
      yield check(line)
    end
  end

  def read(*args)
    check(@input.read(*args))
  end

  def gets
    check(@input.gets)
  end
end
