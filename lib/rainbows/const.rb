# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Const

  RAINBOWS_VERSION = '2.1.0'

  include Unicorn::Const

  RACK_DEFAULTS = Unicorn::HttpRequest::DEFAULTS.update({
    "SERVER_SOFTWARE" => "Rainbows! #{RAINBOWS_VERSION}",

    # using the Rev model, we'll automatically chunk pipe and socket objects
    # if they're the response body.  Unset by default.
    # "rainbows.autochunk" => false,
  })

  # client IO object that supports reading and writing directly
  # without filtering it through the HTTP chunk parser.
  # Maybe we can get this renamed to "rack.io" if it becomes part
  # of the official spec, but for now it is "hack.io"
  CLIENT_IO = "hack.io".freeze

  ERROR_413_RESPONSE = "HTTP/1.1 413 Request Entity Too Large\r\n\r\n"
  ERROR_416_RESPONSE = "HTTP/1.1 416 Requested Range Not Satisfiable\r\n\r\n"

  RACK_INPUT = Unicorn::HttpRequest::RACK_INPUT
  REMOTE_ADDR = Unicorn::HttpRequest::REMOTE_ADDR
end
