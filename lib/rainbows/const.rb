# -*- encoding: binary -*-

module Rainbows

  module Const
    RAINBOWS_VERSION = '0.93.0'

    include Unicorn::Const

    RACK_DEFAULTS = ::Unicorn::HttpRequest::DEFAULTS.merge({

      # we need to observe many of the rules for thread-safety even
      # with Revactor or Rev, so we're considered multithread-ed even
      # when we're not technically...
      "rack.multithread" => true,
      "SERVER_SOFTWARE" => "Rainbows #{RAINBOWS_VERSION}",
    })

    CONN_CLOSE = "Connection: close\r\n"
    CONN_ALIVE = "Connection: keep-alive\r\n"
    LOCALHOST = "127.0.0.1"

  end
end
