# -*- encoding: binary -*-

module Rainbows

  module Const
    RAINBOWS_VERSION = '0.91.1'

    include Unicorn::Const

    RACK_DEFAULTS = Unicorn::HttpRequest::DEFAULTS.update({
      "SERVER_SOFTWARE" => "Rainbows! #{RAINBOWS_VERSION}",

      # using the Rev model, we'll automatically chunk pipe and socket objects
      # if they're the response body.  Unset by default.
      # "rainbows.autochunk" => false,
    })

    CONN_CLOSE = "Connection: close\r\n"
    CONN_ALIVE = "Connection: keep-alive\r\n"

    # client IO object that supports reading and writing directly
    # without filtering it through the HTTP chunk parser.
    # Maybe we can get this renamed to "rack.io" if it becomes part
    # of the official spec, but for now it is "hack.io"
    CLIENT_IO = "hack.io".freeze

    ERROR_413_RESPONSE = "HTTP/1.1 413 Request Entity Too Large\r\n\r\n"

  end
end
