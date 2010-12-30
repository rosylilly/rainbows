# -*- encoding: binary -*-
# :enddoc:
# non-portable body handling for Fiber-based concurrency goes here
# this module is required and included in worker processes only
# this is meant to be included _after_ Rainbows::Response::Body
module Rainbows::Fiber::Body # :nodoc:

  # the sendfile 1.0.0+ gem includes IO#sendfile_nonblock
  if IO.method_defined?(:sendfile_nonblock)
    def write_body_file(body, range)
      sock, n, body = to_io, nil, body_to_io(body)
      offset, count = range ? range : [ 0, body.stat.size ]
      begin
        offset += (n = sock.sendfile_nonblock(body, offset, count))
      rescue Errno::EAGAIN
        kgio_wait_writable
        retry
      rescue EOFError
        break
      end while (count -= n) > 0
      ensure
        close_if_private(body)
    end
  end

  def self.included(klass)
    klass.__send__ :alias_method, :write_body_stream, :write_body_each
  end
end
