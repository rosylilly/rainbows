# -*- encoding: binary -*-
require 'time'
require 'rainbows'

module Rainbows

  class HttpResponse < ::Unicorn::HttpResponse

    def self.write(socket, rack_response, out = [])
      status, headers, body = rack_response

      if Array === out
        status = CODES[status.to_i] || status

        headers.each do |key, value|
          next if SKIP.include?(key.downcase)
          if value =~ /\n/
            out.concat(value.split(/\n/).map! { |v| "#{key}: #{v}\r\n" })
          else
            out << "#{key}: #{value}\r\n"
          end
        end

        socket.write("HTTP/1.1 #{status}\r\n" \
                     "Date: #{Time.now.httpdate}\r\n" \
                     "Status: #{status}\r\n" \
                     "#{out.join('')}\r\n")
      end

      body.each { |chunk| socket.write(chunk) }
      ensure
        body.respond_to?(:close) and body.close rescue nil
    end
  end
end
