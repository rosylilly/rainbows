# -*- encoding: binary -*-

module Rainbows

  module Const
    RAINBOWS_VERSION = '0.9.0'

    include Unicorn::Const

    RACK_DEFAULTS = Unicorn::HttpRequest::DEFAULTS.update({
      "SERVER_SOFTWARE" => "Rainbows! #{RAINBOWS_VERSION}",

      # using the Rev model, we'll automatically chunk pipe and socket objects
      # if they're the response body
      'rainbows.autochunk' => false,
    })

    CONN_CLOSE = "Connection: close\r\n"
    CONN_ALIVE = "Connection: keep-alive\r\n"
    LOCALHOST = Unicorn::HttpRequest::LOCALHOST

    # client IO object that supports reading and writing directly
    # without filtering it through the HTTP chunk parser.
    # Maybe we can get this renamed to "rack.io" if it becomes part
    # of the official spec, but for now it is "hack.io"
    CLIENT_IO = "hack.io".freeze

  end
end
