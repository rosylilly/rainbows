# based on async_examples/async_app.ru by James Tucker
class DeferrableChunkBody
  include EventMachine::Deferrable

  def call(*body)
    body.each do |chunk|
      @body_callback.call("#{chunk.size.to_s(16)}\r\n")
      @body_callback.call(chunk)
      @body_callback.call("\r\n")
    end
  end

  def each(&block)
    @body_callback = block
  end

  def finish
    @body_callback.call("0\r\n\r\n")
  end
end

class AsyncChunkApp
  def call(env)
    body = DeferrableChunkBody.new
    body.callback { body.finish }
    headers = {
      'Content-Type' => 'text/plain',
      'Transfer-Encoding' => 'chunked',
    }
    EM.next_tick {
      env['async.callback'].call([ 200, headers, body ])
    }
    EM.add_timer(1) {
      body.call "Hello "

      EM.add_timer(1) {
        body.call "World #{env['PATH_INFO']}\n"
        body.succeed
      }
    }
    nil
  end
end
run AsyncChunkApp.new
