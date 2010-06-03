# -*- encoding: binary -*-
module Rainbows

# Convert X-Sendfile headers into Rack response bodies that respond
# to the +to_path+ method which allows certain concurrency models to
# serve efficiently using sendfile() or similar.  With multithreaded
# models under Ruby 1.9, IO.copy_stream will be used.
#
# This middleware is recommended for EventMachine users regardless
# of Ruby version and 1.9 users with any Thread-based concurrency
# models.  DO NOT use this middleware if you're proxying \Rainbows!
# with a server (e.g. Apache, Lighttpd) that understands X-Sendfile
# natively.
#
# This does NOT understand X-Accel-Redirect headers intended for
# nginx, that is much more complicated to configure and support
# as it is highly coupled with the corresponding nginx configuration.

class Sendfile < Struct.new(:app)

  # :nodoc:
  HH = Rack::Utils::HeaderHash

  # Body wrapper, this allows us to fall back gracefully to
  # #each in case a given concurrency model does not optimize
  # #to_path calls.
  class Body < Struct.new(:to_io)

    def initialize(path, headers)
      # Rainbows! will try #to_io if #to_path exists to avoid unnecessary
      # open() calls.
      self.to_io = File.open(path, 'rb')

      unless headers['Content-Length']
        stat = to_io.stat
        headers['Content-Length'] = stat.size.to_s if stat.file?
      end
    end

    def to_path
      to_io.path
    end

    # fallback in case our #to_path doesn't get handled for whatever reason
    def each(&block)
      buf = ''
      while to_io.read(0x4000, buf)
        yield buf
      end
    end

    def close
      to_io.close
    end
  end

  def call(env)
    status, headers, body = app.call(env)
    headers = HH.new(headers)
    if path = headers.delete('X-Sendfile')
      body = Body.new(path, headers) unless body.respond_to?(:to_path)
    end
    [ status, headers, body ]
  end
end

end
