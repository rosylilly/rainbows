# -*- encoding: binary -*-
# :enddoc:
module Rainbows

  # acts like tee(1) on an input input to provide a input-like stream
  # while providing rewindable semantics through a File/StringIO
  # backing store.  On the first pass, the input is only read on demand
  # so your Rack application can use input notification (upload progress
  # and like).  This should fully conform to the Rack::InputWrapper
  # specification on the public API.  This class is intended to be a
  # strict interpretation of Rack::InputWrapper functionality and will
  # not support any deviations from it.
  class TeeInput < Unicorn::TeeInput

    # empty class, this is to avoid unecessarily modifying Unicorn::TeeInput
    # when MaxBody::Limit is included
  end
end
