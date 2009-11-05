# -*- encoding: binary -*-

module Rainbows

  module Const
    RAINBOWS_VERSION = '0.5.0'

    include Unicorn::Const

    RACK_DEFAULTS = ::Unicorn::HttpRequest::DEFAULTS.merge({
      "SERVER_SOFTWARE" => "Rainbows! #{RAINBOWS_VERSION}",

      # using the Rev model, we'll automatically chunk pipe and socket objects
      # if they're the response body
      'rainbows.autochunk' => false,
    })

    CONN_CLOSE = "Connection: close\r\n"
    CONN_ALIVE = "Connection: keep-alive\r\n"
    LOCALHOST = "127.0.0.1"

  end
end
