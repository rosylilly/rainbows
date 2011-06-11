# -*- encoding: binary -*-
require "sleepy_penguin"
require "raindrops"

# Like Unicorn itself, this concurrency model is only intended for use
# behind nginx and completely unsupported otherwise.  Even further from
# Unicorn, this isn't even a good idea with normal LAN clients, only nginx!
#
# It does NOT require a thread-safe Rack application at any point, but
# allows streaming data asynchronously via nginx (using the
# "X-Accel-Buffering: no" header to disable buffering).
#
# Unlike Rainbows::Base, this does NOT support persistent
# connections or pipelining.  All \Rainbows! specific configuration
# options are ignored (except Rainbows::Configurator#use).
#
# === RubyGem Requirements
#
# * raindrops 0.6.0 or later
# * sleepy_penguin 3.0.1 or later
module Rainbows::StreamResponseEpoll
  # :stopdoc:
  CODES = Unicorn::HttpResponse::CODES
  HEADER_END = "X-Accel-Buffering: no\r\n\r\n"
  autoload :Client, "rainbows/stream_response_epoll/client"

  def http_response_write(socket, status, headers, body)
    status = CODES[status.to_i] || status
    ep_client = false

    if headers
      # don't set extra headers here, this is only intended for
      # consuming by nginx.
      buf = "HTTP/1.0 #{status}\r\nStatus: #{status}\r\n"
      headers.each do |key, value|
        if value =~ /\n/
          # avoiding blank, key-only cookies with /\n+/
          buf << value.split(/\n+/).map! { |v| "#{key}: #{v}\r\n" }.join
        else
          buf << "#{key}: #{value}\r\n"
        end
      end
      buf << HEADER_END

      case rv = socket.kgio_trywrite(buf)
      when nil then break
      when String # retry, socket buffer may grow
        buf = rv
      when :wait_writable
        ep_client = Client.new(socket, buf)
        body.each { |chunk| ep_client.write(chunk) }
        return ep_client.close
      end while true
    end

    body.each do |chunk|
      if ep_client
        ep_client.write(chunk)
      else
        case rv = socket.kgio_trywrite(chunk)
        when nil then break
        when String # retry, socket buffer may grow
          chunk = rv
        when :wait_writable
          ep_client = Client.new(socket, chunk)
          break
        end while true
      end
    end
    ep_client.close if ep_client
    ensure
      body.respond_to?(:close) and body.close
  end
  # :startdoc:
end
