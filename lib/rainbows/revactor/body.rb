# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Revactor::Body
  # TODO non-blocking splice(2) under Linux
  ALIASES = {
    :write_body_stream => :write_body_each
  }

  if IO.method_defined?(:sendfile_nonblock)
    def write_body_file(client, body, range)
      sock = client.instance_variable_get(:@_io)
      pfx = Revactor::TCP::Socket === client ? :tcp : :unix
      write_complete = T[:"#{pfx}_write_complete", client]
      closed = T[:"#{pfx}_closed", client]
      offset, count = range ? range : [ 0, body.stat.size ]
      begin
        offset += (n = sock.sendfile_nonblock(body, offset, count))
      rescue Errno::EAGAIN
        # The @_write_buffer is empty at this point, trigger the
        # on_readable method which in turn triggers on_write_complete
        # even though nothing was written
        client.controller = Actor.current
        client.__send__(:enable_write_watcher)
        Actor.receive do |filter|
          filter.when(write_complete) {}
          filter.when(closed) { raise Errno::EPIPE }
        end
        retry
      rescue EOFError
        break
      end while (count -= n) > 0
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
