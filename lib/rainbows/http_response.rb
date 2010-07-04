# -*- encoding: binary -*-
require 'time' # for Time#httpdate

# :stopdoc:
module Rainbows::HttpResponse

  CODES = Unicorn::HttpResponse::CODES

  def response_header(response, out)
    status, headers = response
    status = CODES[status.to_i] || status

    headers.each do |key, value|
      next if %r{\A(?:X-Rainbows-|Connection\z|Date\z|Status\z)}i =~ key
      if value =~ /\n/
        # avoiding blank, key-only cookies with /\n+/
        out.concat(value.split(/\n+/).map! { |v| "#{key}: #{v}\r\n" })
      else
        out << "#{key}: #{value}\r\n"
      end
    end

    "HTTP/1.1 #{status}\r\n" \
    "Date: #{Time.now.httpdate}\r\n" \
    "Status: #{status}\r\n" \
    "#{out.join('')}\r\n"
  end

  def write_header(socket, response, out)
    out and socket.write(response_header(response, out))
  end

  def write_response(socket, response, out)
    write_header(socket, response, out)
    write_body(socket, response[2])
  end

  # called after forking
  def self.setup(klass)
    require('rainbows/http_response/body') and
      klass.__send__(:include, Rainbows::HttpResponse::Body)
  end
end
# :startdoc:
