# -*- encoding: binary -*-
# :enddoc:
require 'time' # for Time#httpdate

module Rainbows::Response
  autoload :Body, 'rainbows/response/body'
  autoload :Range, 'rainbows/response/range'

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
    range_class = body_class = klass
    case Rainbows::Const::RACK_DEFAULTS['rainbows.model']
    when :WriterThreadSpawn
      body_class = Rainbows::WriterThreadSpawn::MySocket
      range_class = Rainbows::HttpServer
    when :EventMachine, :NeverBlock
      range_class = nil # :<
    end
    return if body_class.included_modules.include?(Body)
    body_class.__send__(:include, Body)
    sf = IO.respond_to?(:copy_stream) || IO.method_defined?(:sendfile_nonblock)
    if range_class
      range_class.__send__(:include, sf ? Range : NoRange)
    end
  end

  module NoRange
    # dummy method if we can't send range responses
    def make_range!(env, status, headers)
    end
  end
end
