# -*- encoding: binary -*-
# :enddoc:
# non-portable body handling for Fiber-based concurrency goes here
# this module is required and included in worker processes only
# this is meant to be included _after_ Rainbows::Response::Body
module Rainbows::Fiber::Body # :nodoc:

  # TODO non-blocking splice(2) under Linux
  ALIASES = {
    :write_body_stream => :write_body_each
  }

  # the sendfile 1.0.0+ gem includes IO#sendfile_nonblock
  if ::IO.method_defined?(:sendfile_nonblock)
    def write_body_file(client, body)
      sock, off = client.to_io, 0
      begin
        off += sock.sendfile_nonblock(body, off, 0x10000)
      rescue Errno::EAGAIN
        client.wait_writable
      rescue EOFError
        break
      end while true
    end
  else
    ALIASES[:write_body] = :write_body_each
  end

  def self.included(klass)
    ALIASES.each do |new_method, orig_method|
      klass.__send__(:alias_method, new_method, orig_method)
    end
  end
end
