# -*- encoding: binary -*-
# :enddoc:
# only used by synchronous interfaces
module Rainbows::RackInput
  NULL_IO = Unicorn::HttpRequest::NULL_IO
  RACK_INPUT = Unicorn::HttpRequest::RACK_INPUT
  CLIENT_IO = Rainbows::Const::CLIENT_IO

  def self.setup
    const_set(:IC, Unicorn::HttpRequest.input_class)
  end

  def set_input(env, hp, client)
    env[RACK_INPUT] = 0 == hp.content_length ? NULL_IO : IC.new(client, hp)
    env[CLIENT_IO] = client
  end
end
