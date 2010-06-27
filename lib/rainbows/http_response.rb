# -*- encoding: binary -*-
require 'time' # for Time#httpdate

# :stopdoc:
class Rainbows::HttpResponse < ::Unicorn::HttpResponse

  def self.header_string(status, headers, out)
    status = CODES[status.to_i] || status

    headers.each do |key, value|
      next if %r{\AX-Rainbows-}i =~ key
      next if SKIP.include?(key.downcase)
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

  def self.write(socket, rack_response, out = [])
    status, headers, body = rack_response
    out.instance_of?(Array) and
      socket.write(header_string(status, headers, out))

    body.each { |chunk| socket.write(chunk) }
    ensure
      body.respond_to?(:close) and body.close
  end
end
# :startdoc:
