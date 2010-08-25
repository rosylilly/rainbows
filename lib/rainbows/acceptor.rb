# -*- encoding: binary -*-

# :enddoc:
require 'fcntl'

# this should make life easier for Zbatery if compatibility with
# fcntl-crippled platforms is required (or if FD_CLOEXEC is inherited)
# and we want to microptimize away fcntl(2) syscalls.
module Rainbows::Acceptor

  # returns nil if accept fails
  def sync_accept(sock)
    rv = sock.accept
    rv.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
    rv
  rescue Errno::EAGAIN, Errno::ECONNABORTED, Errno::EINTR
  end

  # returns nil if accept fails
  def accept(sock)
    rv = sock.accept_nonblock
    rv.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
    rv
  rescue Errno::EAGAIN, Errno::ECONNABORTED
  end
end
