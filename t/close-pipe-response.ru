# must be run without Rack::Lint since that clobbers to_path
class CloseWrapper < Struct.new(:to_io)
  def each(&block)
    to_io.each(&block)
  end

  def close
    ::File.open(ENV['fifo'], 'wb') do |fp|
      fp.syswrite("CLOSING #{to_io}\n")
      if to_io.respond_to?(:close) && ! to_io.closed?
        to_io.close
      end
    end
  end
end
use Rainbows::DevFdResponse
run(lambda { |env|
  body = 'hello world'
  io = IO.popen("echo '#{body}'", 'rb')
  [ 200,
    {
      'Content-Length' => (body.size + 1).to_s,
      'Content-Type' => 'application/octet-stream',
    },
    CloseWrapper[io] ]
})
