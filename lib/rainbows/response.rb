# -*- encoding: binary -*-
# :enddoc:
require 'time' # for Time#httpdate

module Rainbows::Response

  CODES = Unicorn::HttpResponse::CODES
  CRLF = "\r\n"

  # freeze headers we may set as hash keys for a small speedup
  CONNECTION = "Connection".freeze
  CLOSE = "close"
  KEEP_ALIVE = "keep-alive"
  HH = Rack::Utils::HeaderHash

  def response_header(status, headers)
    status = CODES[status.to_i] || status
    rv = "HTTP/1.1 #{status}\r\n" \
         "Date: #{Time.now.httpdate}\r\n" \
         "Status: #{status}\r\n"
    headers.each do |key, value|
      next if %r{\A(?:X-Rainbows-|Date\z|Status\z)}i =~ key
      if value =~ /\n/
        # avoiding blank, key-only cookies with /\n+/
        rv << value.split(/\n+/).map! { |v| "#{key}: #{v}\r\n" }.join('')
      else
        rv << "#{key}: #{value}\r\n"
      end
    end
    rv << CRLF
  end

  # called after forking
  def self.setup(klass)
    require('rainbows/response/body') and
      klass.__send__(:include, Rainbows::Response::Body)
  end
end
