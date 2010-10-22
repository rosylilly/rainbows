# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Fiber::Rev::Methods
  class Watcher < Rev::IOWatcher
    def initialize(fio, flag)
      @f = fio.f || Fiber.current
      super(fio, flag)
      attach(Rev::Loop.default)
    end

    def on_readable
      @f.resume
    end

    alias on_writable on_readable
  end

  def initialize(*args)
    @f = Fiber.current
    super(*args)
    @r = @w = false
  end

  def close
    @w.detach if @w
    @r.detach if @r
    @r = @w = false
    super
  end

  def wait_writable
    @w ||= Watcher.new(self, :w)
    @w.enable unless @w.enabled?
    Fiber.yield
    @w.disable
  end

  def wait_readable
    @r ||= Watcher.new(self, :r)
    @r.enable unless @r.enabled?
    KATO << @f
    Fiber.yield
    @r.disable
  end
end

[
  Rainbows::Fiber::IO,
  Rainbows::Client,
  # the next two trigger autoload, ugh, oh well...
  Rainbows::Fiber::IO::Socket,
  Rainbows::Fiber::IO::Pipe
].each do |klass|
  klass.__send__(:include, Rainbows::Fiber::Rev::Methods)
end
