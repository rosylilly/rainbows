# -*- encoding: binary -*-
# :enddoc:

# Used to keep track of file offsets in IO#sendfile_nonblock + evented
# models.  We always maintain our own file offsets in userspace because
# because sendfile() implementations offer pread()-like idempotency for
# concurrency (multiple clients can read the same underlying file handle).
class Rainbows::StreamFile < Struct.new(:offset, :to_io)

  def close
    to_io.close
    self.to_io = nil
  end
end
